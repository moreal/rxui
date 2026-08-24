import examples.NestLabBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.NestLabBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Nest Lab output directory"
