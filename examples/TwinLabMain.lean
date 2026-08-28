import examples.TwinLabBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.TwinLabBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Twin Lab output directory"
