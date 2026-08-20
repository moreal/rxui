namespace LeanRx.Cli

inductive GraphFormat where
  | json | dot | html
deriving Repr, BEq

inductive Command where
  | check (moduleName : String)
  | build (moduleName output : String)
  | graph (moduleName : String) (format : GraphFormat)
  | scaffold (output : String)
  | explain (code : String)
  | doctor
deriving Repr, BEq

structure Error where
  code : String
  message : String
deriving Repr, BEq

structure Explanation where
  code : String
  phase : String
  summary : String
  nextAction : String
deriving Repr, BEq

def Explanation.render (value : Explanation) : String :=
  value.code ++ "\n" ++
    "  phase: " ++ value.phase ++ "\n" ++
    "  meaning: " ++ value.summary ++ "\n" ++
    "  next: " ++ value.nextAction

/-- Stable help for the most important public diagnostic boundaries. -/
def explanation? : String → Option Explanation
  | "LRX-SYN-001" => some {
      code := "LRX-SYN-001"
      phase := "CLI or surface syntax"
      summary := "The command or LeanRx surface form does not match a supported grammar."
      nextAction := "Check the command usage or the source-linked syntax location; unsupported forms are not guessed."
    }
  | "LRX-ELAB-020" => some {
      code := "LRX-ELAB-020"
      phase := "CLI module dispatch"
      summary := "The requested component is not registered with this compiler executable."
      nextAction := "Use a registered module or extend the explicit compiler driver registry."
    }
  | "LRX-GRAPH-001" => some {
      code := "LRX-GRAPH-001"
      phase := "graph planning"
      summary := "The declared reactive dependencies contain a cycle."
      nextAction := "Inspect the reported path and spans, then make derived dependencies acyclic."
    }
  | "LRX-TYPE-108" => some {
      code := "LRX-TYPE-108"
      phase := "typed component validation"
      summary := "An event reads a derived value before a supported transaction barrier exists."
      nextAction := "Read source fields in the event or move the computation into a derived node."
    }
  | "LRX-VIEW-005" => some {
      code := "LRX-VIEW-005"
      phase := "safe view validation"
      summary := "A click binding was attached to a non-button element."
      nextAction := "Use a native button so keyboard and activation semantics remain available."
    }
  | "LRX-BE-020" => some {
      code := "LRX-BE-020"
      phase := "Reactive IR lowering"
      summary := "The staged expression uses a construct outside the controlled backend subset."
      nextAction := "Rewrite with supported scalar/dependent operations or add a checked lowering and regression."
    }
  | "LRX-PORT-001" => some {
      code := "LRX-PORT-001"
      phase := "CLI file output"
      summary := "The requested output path does not name a publishable directory."
      nextAction := "Pass a concrete directory path outside an unmanaged existing output."
    }
  | _ => none

/-- Pure command-line parsing; file IO and module dispatch live in the executable. -/
def parse : List String → Except Error Command
  | ["check", moduleName] => .ok (.check moduleName)
  | ["graph", moduleName, "--format", "json"] => .ok (.graph moduleName .json)
  | ["graph", moduleName, "--format", "dot"] => .ok (.graph moduleName .dot)
  | ["graph", moduleName, "--format", "html"] => .ok (.graph moduleName .html)
  | ["scaffold", "--out", output] =>
      if output.isEmpty then
        .error { code := "LRX-SYN-001", message := "scaffold output directory must not be empty" }
      else .ok (.scaffold output)
  | ["explain", code] => .ok (.explain code)
  | ["doctor"] => .ok .doctor
  | ["build", moduleName, "--out", output] =>
      if output.isEmpty then
        .error { code := "LRX-SYN-001", message := "build output directory must not be empty" }
      else .ok (.build moduleName output)
  | _ => .error {
      code := "LRX-SYN-001"
      message := "usage: leanrx (check MODULE | graph MODULE --format json|dot|html | build MODULE --out DIRECTORY | scaffold --out DIRECTORY | explain CODE | doctor)"
    }

end LeanRx.Cli
