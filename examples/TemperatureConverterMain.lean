import examples.TemperatureConverterBuild

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.TemperatureConverterBuild.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Temperature Converter output directory"
