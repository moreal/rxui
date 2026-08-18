import Test.AxiomManifest

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

def main : IO Unit := do
  assertEq "0.1.0-dev" LeanRx.version
  assertEq "" LeanRx.SourceSpan.generated.file
  assertEq 0 LeanRx.SourceSpan.generated.start.byteOffset
  IO.println "LeanRx native smoke tests passed"
