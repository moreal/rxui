import examples.ValidatedFormBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.ValidatedFormBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Validated Form output directory"
