import LeanRx.Component.Dependent
import LeanRx.Component.Model
import LeanRx.Graph.Topological
import LeanRx.IR.Erasure
import LeanRx.Lower.RxExpr

namespace LeanRx

abbrev TabsState (count : Nat) : Schema :=
  .field "selected" (Fin count) .empty

def tabsSelectedField (count : Nat) : Field (TabsState count) (Fin count) := .here

/-- Equal-length, statically nonempty immutable tab inputs. -/
structure TabsProps (n : Nat) where
  private mk ::
  labels : ImmutableProp (Vector String (n + 1))
  panels : ImmutableProp (Vector String (n + 1))

namespace TabsProps

def ofVectors (labels panels : Vector String (n + 1)) : TabsProps n :=
  { labels := ImmutableProp.of "labels" labels
    panels := ImmutableProp.of "panels" panels }

def count (_ : TabsProps n) : Nat := n + 1

end TabsProps

/-- A dependent tabs component. Its constructor requires an initial valid
selection and equal nonempty label/panel vectors. -/
structure TabsSpec (n : Nat) where
  private mk ::
  name : String
  props : TabsProps n
  initialSelected : Fin (n + 1)
  span : SourceSpan := .generated

namespace TabsSpec

def create (name : String) (labels panels : Vector String (n + 1))
    (span : SourceSpan := .generated) : TabsSpec n :=
  { name, props := TabsProps.ofVectors labels panels
    initialSelected := ⟨0, Nat.zero_lt_succ n⟩, span }

/-- Choose a non-default initial tab without accepting Lean's modulo-normalized
`OfNat (Fin n)` coercion. The caller must supply the intended natural and its
strict bound proof. -/
def createAt (name : String) (labels panels : Vector String (n + 1))
    (index : Nat) (valid : index < n + 1)
    (span : SourceSpan := .generated) : TabsSpec n :=
  { name, props := TabsProps.ofVectors labels panels
    initialSelected := ⟨index, valid⟩, span }

def selectEvent (spec : TabsSpec n) : TypedEventSpec (TabsState (n + 1)) (Fin (n + 1)) :=
  TypedEventSpec.assign "select" "index" (tabsSelectedField (n + 1)) spec.span

private abbrev EvalSchema (count : Nat) : Schema :=
  .field "panels" (Vector String count) <| .field "selected" (Fin count) .empty

def selectedPanelExpr (n : Nat) := RxExpr.vectorGet
  (RxExpr.read (.here : Field (EvalSchema (n + 1)) (Vector String (n + 1))))
  (RxExpr.read (.there .here : Field (EvalSchema (n + 1)) (Fin (n + 1))))

private def graphSpecs (spec : TabsSpec n) : Array NodeSpec := #[
  .source "selected" (.fin (n + 1)) spec.span,
  .sink "panel" .string #[{ id := ⟨0⟩, valueType := .fin (n + 1) }]
    "vector.get(props.panels,selected)" spec.span
]

structure Checked (n : Nat) where
  private mk ::
  spec : TabsSpec n
  graph : PlannedGraph
  event : TypedEventSpec (TabsState (n + 1)) (Fin (n + 1))
  erasure : ReactiveIR.ErasureReport

def check (spec : TabsSpec n) : Except ComponentError (Checked n) := do
  if spec.name.isEmpty then
    throw {
      code := "LRX-ELAB-109"
      message := "dependent component name must not be empty"
      spans := #[spec.span]
    }
  let event := spec.selectEvent
  if event.name.isEmpty then
    throw {
      code := "LRX-ELAB-110"
      message := "typed event name must not be empty"
      spans := #[event.span]
    }
  if event.parameterName.isEmpty then
    throw {
      code := "LRX-ELAB-111"
      message := "typed event parameter name must not be empty"
      path := #[event.name]
      spans := #[event.span]
    }
  match Graph.plan (graphSpecs spec) with
  | .error error => throw {
      code := error.code
      message := error.message
      path := error.path
      spans := error.spans
    }
  | .ok graph =>
    match (Lower.rxExpr (selectedPanelExpr n)).assertErasureSafe with
    | .ok erasure => pure { spec, graph, event, erasure }
    | .error error => throw {
        code := error.code
        message := error.message
        spans := #[spec.span]
      }

end TabsSpec

end LeanRx
