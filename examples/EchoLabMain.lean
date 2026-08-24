import examples.EchoLabBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.EchoLabBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Echo Lab output directory"
