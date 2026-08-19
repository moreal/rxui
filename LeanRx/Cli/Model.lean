namespace LeanRx.Cli

inductive GraphFormat where
  | json | dot
deriving Repr, BEq

inductive Command where
  | check (moduleName : String)
  | build (moduleName output : String)
  | graph (moduleName : String) (format : GraphFormat)
deriving Repr, BEq

structure Error where
  code : String
  message : String
deriving Repr, BEq

/-- Pure command-line parsing; file IO and module dispatch live in the executable. -/
def parse : List String → Except Error Command
  | ["check", moduleName] => .ok (.check moduleName)
  | ["graph", moduleName, "--format", "json"] => .ok (.graph moduleName .json)
  | ["graph", moduleName, "--format", "dot"] => .ok (.graph moduleName .dot)
  | ["build", moduleName, "--out", output] =>
      if output.isEmpty then
        .error { code := "LRX-SYN-001", message := "build output directory must not be empty" }
      else .ok (.build moduleName output)
  | _ => .error {
      code := "LRX-SYN-001"
      message := "usage: leanrx (check MODULE | graph MODULE --format json|dot | build MODULE --out DIRECTORY)"
    }

end LeanRx.Cli
