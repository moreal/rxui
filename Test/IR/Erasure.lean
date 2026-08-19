import LeanRx.IR.Erasure

namespace LeanRxTest.IR.Erasure

open LeanRx

def run : IO Unit := do
  let selected : ReactiveIR.Expr String := .vectorGet .string
    (.input (.vector .string 3) 0 "panels") (.input (.fin 3) 1 "selected")
  let report := selected.erasureReport
  unless report.erased == [.vectorLength 3, .finBound 3] &&
      report.inspections.isEmpty && report.operations == ["input", "input", "vector.get"] do
    throw <| IO.userError s!"dependent IR erasure report changed: {repr report}"
  unless ReactiveIR.erasedStaticEvidence (.list (.vector (.fin 4) 2)) ==
      [.finBound 4, .vectorLength 2] do
    throw <| IO.userError "dynamic-list erasure metadata changed"
  match selected.assertErasureSafe with
  | .error error => throw <| IO.userError s!"safe dependent IR failed: {error.code}"
  | .ok _ => pure ()
  let invalid : ReactiveIR.ErasureReport :=
    { inspections := [.finBound 3], operations := ["future.proof.inspect"] }
  match invalid.validate with
  | .ok _ => throw <| IO.userError "proof evidence inspection passed the IR assertion"
  | .error error =>
      unless error.code == "LRX-BE-028" do
        throw <| IO.userError "proof-erasure assertion returned the wrong diagnostic"

example (value : ReactiveIR.Expr α) : value.erasureReport.inspections = [] :=
  ReactiveIR.Expr.erasureReport_no_inspections value

end LeanRxTest.IR.Erasure
