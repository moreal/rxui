import examples.DiamondLabBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.DiamondLabBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Diamond Lab output directory"
