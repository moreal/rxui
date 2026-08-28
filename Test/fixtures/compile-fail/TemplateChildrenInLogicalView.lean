import LeanRx

open LeanRx
open scoped LeanRxDsl

def LogicalMetric (label : String) : LeanRx.Region.LogicalNode :=
  .element "p" [("class", "metric")] [.text label]

/-- The logical fallback shares the typed view's no-children guard
(ADR-0074): a spec-less capitalized head consumes no children, so the
children here would be dropped. -/
def logicalDropped : LeanRx.Region.LogicalNode :=
  jsx% <main> [
    <LogicalMetric label="m"> ["extra"]
  ]
