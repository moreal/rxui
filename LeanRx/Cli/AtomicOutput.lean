namespace LeanRx.Cli.AtomicOutput

private structure Paths where
  parent : System.FilePath
  outputName : String
  bundlePrefix : String
  bundle : System.FilePath
  pointer : System.FilePath
  lock : System.FilePath

private def paths (output : System.FilePath) : IO Paths := do
  let outputName ← match output.fileName with
    | some name => pure name
    | none => throw <| IO.userError "error[LRX-PORT-001]: output must name a directory"
  let parent := output.parent.getD "."
  let unique := s!"{← IO.Process.getPID}-{← IO.monoNanosNow}"
  let bundlePrefix := s!".{outputName}.leanrx-bundle-"
  pure {
    parent
    outputName
    bundlePrefix
    bundle := parent / (bundlePrefix ++ unique)
    pointer := parent / s!".{outputName}.leanrx-pointer-{unique}"
    lock := parent / s!".{outputName}.leanrx.lock"
  }

private def metadata? (path : System.FilePath) : IO (Option IO.FS.FileType) :=
  try pure <| some (← path.symlinkMetadata).type
  catch _ => pure none

private def removeIfPresent (path : System.FilePath) : IO Unit := do
  match ← metadata? path with
  | none => pure ()
  | some .dir => IO.FS.removeDirAll path
  | some _ => IO.FS.removeFile path

private partial def openLock (path : System.FilePath) : IO IO.FS.Handle := do
  match ← metadata? path with
  | none => try
      return ← IO.FS.Handle.mk path .writeNew
      catch error =>
        if (← metadata? path).isSome then return ← openLock path else throw error
  | some .file => return ← IO.FS.Handle.mk path .readWrite
  | some _ => return ← (throw (IO.userError
      "error[LRX-PORT-004]: atomic output lock must be a regular file") : IO IO.FS.Handle)

private def createPointer (target : String) (pointer : System.FilePath) : IO Unit := do
  let _ ← IO.Process.run { cmd := "ln", args := #["-s", target, pointer.toString] }

private def readPointer (output : System.FilePath) : IO String := do
  let value ← IO.Process.run { cmd := "readlink", args := #[output.toString] }
  pure value.trimAscii.toString

private def ownerMarker (paths : Paths) : String :=
  s!"LeanRx managed bundle for {paths.outputName}\n"

private def isOwnedBundle (paths : Paths) (bundle : System.FilePath) : IO Bool := do
  let marker := bundle / ".leanrx-bundle-owner"
  match ← metadata? marker with
  | some .file => pure ((← IO.FS.readFile marker) == ownerMarker paths)
  | _ => pure false

private def checkedOldTarget (paths : Paths) (output : System.FilePath) : IO (Option String) := do
  match ← metadata? output with
  | none => pure none
  | some .symlink =>
      let target ← readPointer output
      unless target.startsWith paths.bundlePrefix &&
          (System.FilePath.mk target).fileName == some target do
        throw <| IO.userError "error[LRX-PORT-002]: output points outside LeanRx bundle storage"
      pure (some target)
  | some _ =>
      throw <| IO.userError
        "error[LRX-PORT-003]: existing output must be a LeanRx atomic bundle pointer"

private def cleanupOlderBundles (paths : Paths) (keep : List String) : IO Unit := do
  for entry in ← paths.parent.readDir do
    if entry.fileName.startsWith paths.bundlePrefix && !keep.contains entry.fileName &&
        (← isOwnedBundle paths entry.path) then
      removeIfPresent entry.path

/-- Publish a complete sibling bundle through an atomically replaced symbolic
link. Every observable output path is either the prior or new complete bundle. -/
def replaceDirectory (output : System.FilePath)
    (generate : System.FilePath → IO Unit) : IO Unit := do
  let paths ← paths output
  IO.FS.createDirAll paths.parent
  let lock ← openLock paths.lock
  lock.lock
  try
    let oldTarget ← checkedOldTarget paths output
    removeIfPresent paths.bundle
    removeIfPresent paths.pointer
    try
      generate paths.bundle
      IO.FS.writeFile (paths.bundle / ".leanrx-bundle-owner") (ownerMarker paths)
      createPointer paths.bundle.fileName.get! paths.pointer
      cleanupOlderBundles paths <| paths.bundle.fileName.get! :: oldTarget.toList
    catch error =>
      removeIfPresent paths.pointer
      removeIfPresent paths.bundle
      throw error
    try
      IO.FS.rename paths.pointer output
    catch error =>
      removeIfPresent paths.pointer
      removeIfPresent paths.bundle
      throw error
    pure ()
  finally
    lock.unlock

end LeanRx.Cli.AtomicOutput
