import examples.FilterLabBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.FilterLabBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Filter Lab output directory"
