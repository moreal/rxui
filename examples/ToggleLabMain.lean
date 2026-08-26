import examples.ToggleLabBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.ToggleLabBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Toggle Lab output directory"
