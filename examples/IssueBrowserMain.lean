import examples.IssueBrowserBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.IssueBrowserBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Issue Browser output directory"
