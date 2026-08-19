import LeanRx.Cli.Driver

def main (args : List String) : IO UInt32 := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  LeanRx.Cli.Driver.run values
