namespace LeanRx.Cli

inductive Command where
  | check (moduleName : String)
  | build (moduleName output : String)
  | graph (moduleName : String)
deriving Repr, BEq

structure Error where
  code : String
  message : String
deriving Repr, BEq

/-- Pure command-line parsing; file IO and module dispatch live in the executable. -/
def parse : List String → Except Error Command
  | ["check", moduleName] => .ok (.check moduleName)
  | ["graph", moduleName] => .ok (.graph moduleName)
  | ["build", moduleName, "--out", output] =>
      if output.isEmpty then
        .error { code := "LRX-CLI-002", message := "build output directory must not be empty" }
      else .ok (.build moduleName output)
  | _ => .error {
      code := "LRX-CLI-002"
      message := "usage: leanrx (check MODULE | graph MODULE | build MODULE --out DIRECTORY)"
    }

end LeanRx.Cli
