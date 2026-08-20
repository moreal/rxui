import LeanRx

open LeanRx.Region

def invalid : PositionalResult :=
  { mounted := [{ token := 0, node := .text "a" }]
    nextToken := 0
    disposed := []
    created := 0
    scalarUpdates := 0 }
