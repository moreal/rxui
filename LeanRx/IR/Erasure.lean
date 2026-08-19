import LeanRx.IR.Reactive

namespace LeanRx.ReactiveIR

/-- Static evidence present in Lean types but absent from runtime values. -/
inductive StaticEvidence where
  | vectorLength (length : Nat)
  | finBound (bound : Nat)
deriving Repr, BEq, DecidableEq

/-- Evidence erased by the ABI, including evidence nested in vector elements. -/
def erasedStaticEvidence : RuntimeTypeId → List StaticEvidence
  | .bool | .string | .int | .nat => []
  | .vector element length => erasedStaticEvidence element ++ [.vectorLength length]
  | .fin bound => [.finBound bound]
  | .record _ => []
  | .list element => erasedStaticEvidence element

/-- Result of traversing typed Reactive IR. `inspections` is deliberately
separate: backend emission is forbidden when it is nonempty. -/
structure ErasureReport where
  erased : List StaticEvidence := []
  inspections : List StaticEvidence := []
  operations : List String := []
deriving Repr, BEq

namespace ErasureReport

def combine (left right : ErasureReport) : ErasureReport :=
  { erased := left.erased ++ right.erased
    inspections := left.inspections ++ right.inspections
    operations := left.operations ++ right.operations }

def record (operation : String) (report : ErasureReport) : ErasureReport :=
  { report with operations := report.operations ++ [operation] }

structure Error where
  code : String
  message : String
deriving Repr, BEq

/-- Fail-closed assertion consumed by every Reactive IR emitter. -/
def validate (report : ErasureReport) : Except Error Unit := do
  unless report.inspections.isEmpty do
    throw {
      code := "LRX-BE-028"
      message := "Reactive IR attempts to inspect proof-erased static evidence"
    }

end ErasureReport

namespace Expr

private def erasedRuntime (runtime : RuntimeTypeId) : List StaticEvidence :=
  erasedStaticEvidence runtime

/-- Structural proof-erasure analysis. Fin values may be used as array indices,
but their bound proofs and vector lengths are never runtime operands. -/
def erasureReport : {α : Type} → Expr α → ErasureReport
  | _, .literal _ => { operations := ["literal"] }
  | _, .input runtime _ _ =>
      { erased := erasedRuntime runtime.id, operations := ["input"] }
  | _, .unary _ value => (erasureReport value).record "unary"
  | _, .binary _ left right =>
      (ErasureReport.combine (erasureReport left) (erasureReport right)).record "binary"
  | _, .conditional condition yes no =>
      (ErasureReport.combine (erasureReport condition)
        (ErasureReport.combine (erasureReport yes) (erasureReport no))).record "conditional"
  | _, .vectorGet _ values index =>
      (ErasureReport.combine (erasureReport values) (erasureReport index)).record "vector.get"

/-- The current closed IR has no constructor that can inspect erased evidence. -/
theorem erasureReport_no_inspections (value : Expr α) :
    value.erasureReport.inspections = [] := by
  induction value with
  | literal | input => rfl
  | unary op value ih => simpa [erasureReport, ErasureReport.record] using ih
  | binary op left right leftIH rightIH =>
      simp [erasureReport, ErasureReport.record, ErasureReport.combine, leftIH, rightIH]
  | conditional condition yes no conditionIH yesIH noIH =>
      simp [erasureReport, ErasureReport.record, ErasureReport.combine,
        conditionIH, yesIH, noIH]
  | vectorGet element values index valuesIH indexIH =>
      simp [erasureReport, ErasureReport.record, ErasureReport.combine, valuesIH, indexIH]

def assertErasureSafe (value : Expr α) : Except ErasureReport.Error ErasureReport := do
  let report := value.erasureReport
  report.validate
  pure report

end Expr

end LeanRx.ReactiveIR
