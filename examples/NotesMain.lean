import examples.NotesBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.NotesBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Notes output directory"
