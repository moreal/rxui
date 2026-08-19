import examples.CounterBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.CounterBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Counter output directory"
