import LeanRx

namespace LeanRxExamples.GraphLab

open LeanRx

abbrev ParitySchema : Schema :=
  .field "count" Int <| .field "parity" Int <| .field "downstream" Int .empty

def parityCount : Field ParitySchema Int := .here
def parity : Field ParitySchema Int := .there .here
def downstream : Field ParitySchema Int := .there (.there .here)

def parityAllInt : AllInt ParitySchema :=
  .field (.field (.field .empty))

open scoped LeanRxDsl in
/-- Staged with `rx%`; each tree matches the former hand-written constructor form. -/
def parityExpr := rx% parityCount % 2
open scoped LeanRxDsl in
def downstreamExpr := rx% parity + 100

def paritySpec : IntProgramSpec ParitySchema :=
  { allInt := parityAllInt
    sourceCount := 1
    values :=
      [ .source parityCount
      , .derived parity parityExpr
      , .derived downstream downstreamExpr
      ]
    sinks :=
      [ .observe "paritySink" (RxExpr.read parity)
      , .observe "downstreamSink" (RxExpr.read downstream)
      ] }

end LeanRxExamples.GraphLab
