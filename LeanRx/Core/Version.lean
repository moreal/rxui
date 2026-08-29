namespace LeanRx

/-- Version embedded in deterministic compiler artifacts. -/
def version : String := "0.1.0-dev"

/-- Exact Lean toolchain expected by this compiler build. -/
def leanToolchain : String := "leanprover/lean4:v4.33.0"

/-- Major internal JavaScript runtime ABI version. -/
def runtimeAbi : Nat := 19

end LeanRx
