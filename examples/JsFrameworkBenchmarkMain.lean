import examples.JsFrameworkBenchmarkBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.JsFrameworkBenchmarkBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected JS framework benchmark output directory"
