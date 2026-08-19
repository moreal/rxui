namespace LeanRx.Cli.AtomicOutput

private def sibling (output : System.FilePath) (suffix : String) : IO System.FilePath := do
  let name ← match output.fileName with
    | some name => pure name
    | none => throw <| IO.userError "error[LRX-PORT-001]: output must name a directory"
  let process := toString (← IO.Process.getPID)
  pure <| output.withFileName s!".{name}.leanrx-{suffix}-{process}"

private def removeIfPresent (path : System.FilePath) : IO Unit := do
  if ← path.pathExists then IO.FS.removeDirAll path

/-- Generate a complete sibling directory and publish it with one rename. Existing
output is restored if publication fails; partial generation is never observable. -/
def replaceDirectory (output : System.FilePath)
    (generate : System.FilePath → IO Unit) : IO Unit := do
  let staging ← sibling output "stage"
  let backup ← sibling output "backup"
  removeIfPresent staging
  if ← backup.pathExists then
    if ← output.pathExists then removeIfPresent backup
    else IO.FS.rename backup output
  try
    generate staging
  catch error =>
    removeIfPresent staging
    throw error
  let hadOutput ← output.pathExists
  if hadOutput then IO.FS.rename output backup
  try
    IO.FS.rename staging output
  catch error =>
    if hadOutput && (← backup.pathExists) then IO.FS.rename backup output
    removeIfPresent staging
    throw error
  removeIfPresent backup

end LeanRx.Cli.AtomicOutput
