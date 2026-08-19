import examples.DependentTabsBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.DependentTabsBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Dependent Tabs output directory"
