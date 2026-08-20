import LeanRx

open LeanRx.Region

def invalid : ConditionalResult :=
  { mounted := { token := 0, branch := true, node := .text "a" }
    nextToken := 0
    disposed := []
    replacements := 0
    scalarUpdates := 0 }
