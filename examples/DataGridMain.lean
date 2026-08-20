import examples.DataGridBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.DataGridBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Data Grid output directory"
