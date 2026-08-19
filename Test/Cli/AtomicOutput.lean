import LeanRx.Cli.AtomicOutput

namespace LeanRxTest.Cli.AtomicOutput

private def assertFile (path : System.FilePath) (expected : String) : IO Unit := do
  let actual ← IO.FS.readFile path
  unless actual == expected do
    throw <| IO.userError s!"expected {expected}, got {actual}"

def run : IO Unit := IO.FS.withTempDir fun parent => do
  let output := parent / "bundle"
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "sentinel") "old"
  try
    LeanRx.Cli.AtomicOutput.replaceDirectory output fun staging => do
      IO.FS.createDirAll staging
      IO.FS.writeFile (staging / "partial") "partial"
      throw <| IO.userError "injected generation failure"
    throw <| IO.userError "atomic output accepted an injected failure"
  catch error =>
    unless error.toString.contains "injected generation failure" do throw error
  assertFile (output / "sentinel") "old"
  if ← (output / "partial").pathExists then
    throw <| IO.userError "partial output escaped failed staging"
  IO.FS.writeFile (output / "stale") "stale"
  LeanRx.Cli.AtomicOutput.replaceDirectory output fun staging => do
    IO.FS.createDirAll staging
    IO.FS.writeFile (staging / "fresh") "fresh"
  assertFile (output / "fresh") "fresh"
  if ← (output / "stale").pathExists then
    throw <| IO.userError "atomic replacement retained a stale artifact"

end LeanRxTest.Cli.AtomicOutput
