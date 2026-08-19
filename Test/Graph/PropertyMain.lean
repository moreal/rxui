import Test.Graph.Properties

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  let seed ← match values with
    | [] => pure 195936478
    | value :: _ => match value.toNat? with
      | some seed => pure seed
      | none => throw <| IO.userError s!"invalid property seed: {value}"
  LeanRxTest.Graph.Properties.runWithSeed seed
  IO.println s!"graph properties passed: seed={seed} cases=40"
