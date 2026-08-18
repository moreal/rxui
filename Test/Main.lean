import LeanRx

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

def main : IO Unit := do
  assertEq "0.1.0-dev" LeanRx.version
  IO.println "LeanRx native smoke tests passed"
