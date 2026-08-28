import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int .empty
def countField : Field S Int := .here

def metricValue := rx% s!"Count: {countField}"

def Metric (value : RxExpr S deps String) : View S :=
  jsx% <p role="status"> [ {"metric": value} ]

/-- A spec-less capitalized head is an ordinary application (ADR-0039) and
consumes no children; non-empty children here used to vanish silently
(ADR-0073 OQ1) and are now rejected (ADR-0074). -/
def dropped : View S :=
  jsx% <main> [
    <Metric value={metricValue}> ["extra"]
  ]
