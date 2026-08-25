import examples.BranchLabBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.BranchLabBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Branch Lab output directory"
