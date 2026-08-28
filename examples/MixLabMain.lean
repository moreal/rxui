import examples.MixLabBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.MixLabBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Mix Lab output directory"
