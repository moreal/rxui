import LeanRx

open LeanRx.Region

def invalid : KeyedResult :=
  { mounted := [{ token := 0, key := 1, node := .text "a" }]
    nextToken := 0
    disposed := []
    created := 0
    moved := 0
    scalarUpdates := 0 }
