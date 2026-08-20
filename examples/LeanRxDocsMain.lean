import examples.LeanRxDocsBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.LeanRxDocsBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected LeanRx docs output directory"
