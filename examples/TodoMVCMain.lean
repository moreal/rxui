import examples.TodoMVCBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.TodoMVCBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected TodoMVC output directory"
