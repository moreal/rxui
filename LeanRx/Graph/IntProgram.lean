import LeanRx.Graph.Topological
import LeanRx.Proofs.DependencySound
import LeanRx.Proofs.PropagationSound

namespace LeanRx

/-- Evidence that every slot in a schema belongs to the homogeneous `Int` proof subset. -/
inductive AllInt : Schema.{0} → Type 1 where
  | empty : AllInt .empty
  | field (tail : AllInt Γ) : AllInt (.field name Int Γ)

namespace AllInt

def storeFrom : {Γ : Schema.{0}} → AllInt Γ → Nat → Abstract.Store → Store Γ
  | _, .empty, _, _ => .empty
  | _, .field tail, offset, store =>
      .cons (store offset) (tail.storeFrom (offset + 1) store)

theorem get_storeFrom_congr {Γ : Schema.{0}} (allInt : AllInt Γ) (offset : Nat)
    (left right : Abstract.Store) {α : Type} (field : Field Γ α)
    (equal : left (offset + field.index) = right (offset + field.index)) :
    (allInt.storeFrom offset left).get field =
      (allInt.storeFrom offset right).get field := by
  induction allInt generalizing α offset with
  | empty => exact nomatch field
  | field tail ih =>
      cases field with
      | here =>
          change left offset = right offset
          simpa [Field.index] using equal
      | there field =>
          simp only [storeFrom, Store.get]
          apply ih (offset := offset + 1) field
          simpa [Field.index, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using equal

def store (allInt : AllInt Γ) (source : Abstract.Store) : Store Γ :=
  allInt.storeFrom 0 source

end AllInt

namespace RxExpr

/-- Interpret an all-`Int` staged expression in the homogeneous proof model.
Its dependency law is inherited from `eval_congr_on_deps`. -/
def toAbstractEval (allInt : AllInt Γ) (expr : RxExpr Γ deps Int) : Abstract.Eval :=
  { deps := deps.ids
    run := fun store => expr.eval (allInt.store store)
    congr := by
      intro left right agree
      apply RxExpr.eval_congr_on_deps
      intro _ field member
      apply AllInt.get_storeFrom_congr allInt 0 left right field
      simpa only [Nat.zero_add] using agree field.index member }

end RxExpr

inductive IntValueSpec (Γ : Schema.{0}) where
  | source (field : Field Γ Int) (span : SourceSpan := .generated)
  | derived (field : Field Γ Int) (expr : RxExpr Γ deps Int)
      (span : SourceSpan := .generated)

namespace IntValueSpec

def field : IntValueSpec Γ → Field Γ Int
  | .source field _ => field
  | .derived field _ _ => field

def span : IntValueSpec Γ → SourceSpan
  | .source _ span => span
  | .derived _ _ span => span

def isSource : IntValueSpec Γ → Bool
  | .source _ _ => true
  | .derived _ _ _ => false

def isDerived : IntValueSpec Γ → Bool
  | .source _ _ => false
  | .derived _ _ _ => true

end IntValueSpec

inductive IntSinkSpec (Γ : Schema.{0}) where
  | observe (name : String) (expr : RxExpr Γ deps Int)
      (span : SourceSpan := .generated)

structure IntProgramSpec (Γ : Schema.{0}) where
  allInt : AllInt Γ
  sourceCount : Nat
  values : List (IntValueSpec Γ)
  sinks : List (IntSinkSpec Γ)

namespace IntProgramSpec

private def deps (ids : List Nat) : Array TypedNodeRef :=
  ids.toArray.map fun id => { id := ⟨id⟩, valueType := .int }

private def valueNodeSpecs : List (IntValueSpec Γ) → List NodeSpec
  | [] => []
  | .source field span :: rest =>
      .source field.name .int span :: valueNodeSpecs rest
  | .derived field expr span :: rest =>
      .derived field.name .int (deps expr.dependencies.ids) expr.debug span ::
        valueNodeSpecs rest

private def sinkNodeSpecs : List (IntSinkSpec Γ) → List NodeSpec
  | [] => []
  | .observe name expr span :: rest =>
      .sink name .int (deps expr.dependencies.ids) expr.debug span :: sinkNodeSpecs rest

def nodeSpecs (spec : IntProgramSpec Γ) : Array NodeSpec :=
  (valueNodeSpecs spec.values ++ sinkNodeSpecs spec.sinks).toArray

def derivedSteps (allInt : AllInt Γ) : Nat → List (IntValueSpec Γ) →
    List Abstract.DerivedStep
  | _, [] => []
  | id, .source _ _ :: rest => derivedSteps allInt (id + 1) rest
  | id, .derived _ expr _ :: rest =>
      { id, evaluator := expr.toAbstractEval allInt } :: derivedSteps allInt (id + 1) rest

def sinkSteps (allInt : AllInt Γ) : List (IntSinkSpec Γ) →
    List Abstract.SinkStep
  | [] => []
  | .observe name expr _ :: rest =>
      { name, evaluator := expr.toAbstractEval allInt } :: sinkSteps allInt rest

def program (spec : IntProgramSpec Γ) : Abstract.Program :=
  { sourceCount := spec.sourceCount
    derived := derivedSteps spec.allInt 0 spec.values
    sinks := sinkSteps spec.allInt spec.sinks }

private def fieldsAlignedFrom : Nat → List (IntValueSpec Γ) → Bool
  | _, [] => true
  | index, value :: rest =>
      decide (value.field.index = index) && fieldsAlignedFrom (index + 1) rest

def alignmentValid (spec : IntProgramSpec Γ) : Bool :=
  decide (spec.values.length = Γ.size) && fieldsAlignedFrom 0 spec.values

def sourceShapeValid (spec : IntProgramSpec Γ) : Bool :=
  decide (spec.sourceCount ≤ spec.values.length) &&
    (spec.values.take spec.sourceCount).all IntValueSpec.isSource &&
    (spec.values.drop spec.sourceCount).all IntValueSpec.isDerived

end IntProgramSpec

/-- One privately constructed source of both the planned executable graph and
the kernel-checked homogeneous proof program. -/
structure CheckedIntProgram where
  private mk ::
  planned : PlannedGraph
  program : Abstract.Program
  wellFormed : program.WellFormed

namespace Graph

/-- Plan typed indexed expressions and derive the M2 proof program from those
same expressions. No caller-authored dependency/equality/evaluator metadata is used. -/
def planInt (spec : IntProgramSpec Γ) : Except GraphError CheckedIntProgram :=
  if spec.alignmentValid then
    if spec.sourceShapeValid then
      match plan spec.nodeSpecs with
      | .error error => .error error
      | .ok planned =>
        let program := spec.program
        if checked : program.checkWellFormed = true then
            .ok <| CheckedIntProgram.mk planned program <|
              Abstract.Program.wellFormed_of_check program checked
        else
          .error {
            code := "LRX-PROOF-002"
            message := "all-Int proof adapter requires sources first and derived declarations in dependency order"
          }
    else
      .error {
        code := "LRX-TYPE-008"
        message := "typed graph sources must be exactly the declared leading value prefix"
      }
  else
    .error {
      code := "LRX-TYPE-007"
      message := "typed graph values must cover schema fields in declaration order"
    }

end Graph

end LeanRx
