import LeanRx

namespace LeanRxExamples.DataGrid

open LeanRx.Grid

/-- The M10 dogfood is deliberately fixed at 10,000 rows so benchmark variants
cannot quietly compare different workloads. -/
def spec : Spec := Spec.create
  "LeanRx 10k Data Grid <img src=x onerror=\"globalThis.gridXss=true\">"

end LeanRxExamples.DataGrid
