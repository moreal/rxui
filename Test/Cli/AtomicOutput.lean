import LeanRx.Cli.AtomicOutput

namespace LeanRxTest.Cli.AtomicOutput

private def assertFile (path : System.FilePath) (expected : String) : IO Unit := do
  let actual ← IO.FS.readFile path
  unless actual == expected do
    throw <| IO.userError s!"expected {expected}, got {actual}"

def run : IO Unit := IO.FS.withTempDir fun parent => do
  let output := parent / "bundle"
  LeanRx.Cli.AtomicOutput.replaceDirectory output fun staging => do
    IO.FS.createDirAll staging
    IO.FS.writeFile (staging / "sentinel") "old"
  unless (← output.symlinkMetadata).type == .symlink do
    throw <| IO.userError "atomic output is not a stable publication pointer"
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
  unless (← output.symlinkMetadata).type == .symlink do
    throw <| IO.userError "atomic replacement lost its publication pointer"
  let legacy := parent / "legacy"
  IO.FS.createDirAll legacy
  IO.FS.writeFile (legacy / "sentinel") "preserved"
  try
    LeanRx.Cli.AtomicOutput.replaceDirectory legacy fun _ => pure ()
    throw <| IO.userError "atomic output accepted an unmanaged destination"
  catch error =>
    unless error.toString.contains "LRX-PORT-003" do throw error
  assertFile (legacy / "sentinel") "preserved"
  let external := parent / "external"
  IO.FS.createDirAll external
  IO.FS.writeFile (external / "sentinel") "external"
  let hostileBundle := parent / ".bundle.leanrx-bundle-hostile"
  let _ ← IO.Process.run {
    cmd := "ln", args := #["-s", external.toString, hostileBundle.toString]
  }
  LeanRx.Cli.AtomicOutput.replaceDirectory output fun staging => do
    IO.FS.createDirAll staging
    IO.FS.writeFile (staging / "safe") "safe"
  assertFile (external / "sentinel") "external"
  if ← hostileBundle.pathExists then
    throw <| IO.userError "hostile managed-prefix symlink survived cleanup"
  let lockTarget := parent / "lock-target"
  IO.FS.writeFile lockTarget "preserve"
  let poisonedOutput := parent / "poison"
  let poisonedLock := parent / ".poison.leanrx.lock"
  let _ ← IO.Process.run {
    cmd := "ln", args := #["-s", lockTarget.toString, poisonedLock.toString]
  }
  try
    LeanRx.Cli.AtomicOutput.replaceDirectory poisonedOutput fun _ => pure ()
    throw <| IO.userError "atomic output followed a poisoned lock path"
  catch error =>
    unless error.toString.contains "LRX-PORT-004" do throw error
  assertFile lockTarget "preserve"

end LeanRxTest.Cli.AtomicOutput
