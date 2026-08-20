import LeanRx.Cli.AtomicOutput
import LeanRx.Cli.Model
import examples.CounterBuild
import examples.LeanRxDocsBuild

namespace LeanRx.Cli.Driver

open LeanRxExamples.Counter
open LeanRxExamples.LeanRxDocs

private def unknownModule (moduleName : String) : IO UInt32 := do
  IO.eprintln s!"error[LRX-ELAB-020]: unknown component module {moduleName}"
  pure 1

private def componentError (error : ComponentError) : IO UInt32 := do
  IO.eprintln error.render
  pure 1

/-- `check` runs every pure backend validity phase without writing artifacts. -/
def checkBackend (checked : CheckedComponent Γ) : Except Js.Error Unit := do
  let emitted ← Backend.Component.emit "Counter.mjs" checked
  let _ ← Js.Printer.module .readable emitted.module
  let _ ← Js.Printer.module .compact emitted.module

private def checkComponent (moduleName : String) (checked : CheckedComponent Γ) : IO UInt32 :=
  match checkBackend checked with
  | .error error => do
      IO.eprintln s!"error[{error.code}]: {error.message}"
      pure 1
  | .ok _ => do
      IO.println s!"check {moduleName}"
      IO.println s!"  component: {checked.spec.name}"
      IO.println s!"  graph: {checked.graph.graph.nodes.size} nodes / {checked.graph.schedule.order.size} scheduled"
      IO.println s!"  values: {checked.sourceCount} source / {checked.spec.values.size - checked.sourceCount} derived"
      IO.println s!"  view: {checked.view.textSinks.length} text sinks / {checked.spec.events.size} events"
      IO.println "  backend: readable + compact JavaScript valid"
      IO.println "  result: ok"
      pure 0

private def graphComponent (format : Cli.GraphFormat)
    (checked : CheckedComponent Γ) : IO UInt32 := do
  IO.println <| match format with
    | .json => checked.graph.toJson
    | .dot => checked.graph.toDot
    | .html => checked.graph.toHtml
  pure 0

private def starterSource : String := String.intercalate "\n" [
  "import LeanRx",
  "",
  "namespace LeanRxStarter",
  "",
  "open LeanRx",
  "",
  "abbrev AppSchema : Schema := .field \"count\" Int .empty",
  "",
  "def count : Field AppSchema Int := .here",
  "",
  "def countText :=",
  "  RxExpr.binary .stringAppend (RxExpr.literal (.string \"Count: \"))",
  "    (RxExpr.unary .intToString (RxExpr.read count))",
  "",
  "def increment : EventSpec AppSchema :=",
  "  { name := \"increment\"",
  "    update := .set count <| RxExpr.binary .intAdd",
  "      (RxExpr.read count) (RxExpr.literal (.int 1)) }",
  "",
  "def view : View AppSchema := View.node .main [",
  "  View.node .h1 [.text \"LeanRx starter\"],",
  "  View.node .button [.text \"Increment\"]",
  "    (attrs := [.buttonType .button])",
  "    (events := [{ kind := .click, eventName := \"increment\" }]),",
  "  View.node .p [.scalarText \"countText\" countText]",
  "]",
  "",
  "def spec : ComponentSpec AppSchema :=",
  "  { name := \"StarterApp\"",
  "    values := #[ValueSpec.state count (.int 0)]",
  "    events := #[increment]",
  "    view }",
  "",
  "def checked := spec.check",
  "",
  "end LeanRxStarter",
  ""
]

private def starterReadme : String := String.intercalate "\n" [
  "# LeanRx starter component",
  "",
  "`App.lean` uses only the public LeanRx API. Copy it into a Lake package that depends on LeanRx,",
  "then run `lake env lean App.lean` before adding a project-specific build executable.",
  "",
  "This repository is not yet a released package, so the scaffold deliberately does not invent a",
  "remote dependency URL or license. See the LeanRx language guide and support matrix first.",
  ""
]

private def scaffoldInto (directory : System.FilePath) : IO Unit := do
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "App.lean") starterSource
  IO.FS.writeFile (directory / "README.md") starterReadme

private def scaffold (output : String) : IO UInt32 := do
  LeanRx.Cli.AtomicOutput.replaceDirectory ⟨output⟩ scaffoldInto
  IO.println "scaffold"
  IO.println s!"  output: {output}"
  IO.println "  files: App.lean, README.md"
  IO.println "  result: ok"
  pure 0

private def toolVersion (command : String) (args : Array String) : IO (Option String) := do
  try
    let output ← IO.Process.output { cmd := command, args }
    if output.exitCode == 0 then
      let value := output.stdout.trimAscii.toString
      pure (if value.isEmpty then none else some value)
    else pure none
  catch _ => pure none

private def doctorLine (ok : Bool) (name detail : String) : IO Unit :=
  IO.println s!"  [{if ok then "ok" else "error"}] {name}: {detail}"

private def doctor : IO UInt32 := do
  let toolchain ← try
    pure (← IO.FS.readFile "lean-toolchain").trimAscii.toString
  catch _ => pure "<missing>"
  let node ← toolVersion "node" #["--version"]
  let pnpm ← toolVersion "corepack" #["pnpm", "--version"]
  let playwright ← toolVersion "corepack" #["pnpm", "exec", "playwright", "--version"]
  let mut hostsOk := true
  for host in ["runtime/leanrx_dom.mjs", "runtime/leanrx_host.mjs",
      "runtime/leanrx_region.mjs", "runtime/leanrx_effects.mjs",
      "runtime/leanrx_issue_ports.mjs"] do
    unless ← (System.FilePath.mk host).pathExists do hostsOk := false
  let compilerOk := match CounterSyntax_check with
    | .ok checked => (checkBackend checked).isOk
    | .error _ => false
  let toolchainOk := toolchain == LeanRx.leanToolchain
  let nodeOk := node.any Cli.nodeVersionCompatible
  let pnpmOk := pnpm.any Cli.pnpmVersionCompatible
  let playwrightOk := playwright.any Cli.playwrightVersionCompatible
  let chromium ← if nodeOk && playwrightOk then
    toolVersion "node" #["-e", String.intercalate "" [
      "const fs=require('node:fs');",
      "const {chromium}=require('@playwright/test');",
      "const p=chromium.executablePath();",
      "if(!fs.existsSync(p))process.exit(1);process.stdout.write(p);"
    ]]
  else pure none
  let chromiumOk := chromium.isSome
  let ready := toolchainOk && nodeOk && pnpmOk && playwrightOk && chromiumOk &&
    hostsOk && compilerOk
  IO.println "LeanRx doctor"
  doctorLine true "compiler" LeanRx.version
  doctorLine toolchainOk "toolchain" toolchain
  doctorLine true "runtime ABI" (toString LeanRx.runtimeAbi)
  doctorLine nodeOk "node" (node.getD "unavailable")
  doctorLine pnpmOk "pnpm" (pnpm.getD "unavailable")
  doctorLine playwrightOk "playwright" (playwright.getD "unavailable")
  doctorLine chromiumOk "chromium" (if chromiumOk then "installed" else "unavailable")
  doctorLine hostsOk "browser hosts" (if hostsOk then "present" else "missing")
  doctorLine compilerOk "backend smoke" (if compilerOk then "valid" else "failed")
  IO.println s!"  result: {if ready then "ready" else "not ready"}"
  pure (if ready then 0 else 1)

private def explain (code : String) : IO UInt32 :=
  match Cli.explanation? code with
  | some value => do
      IO.println value.render
      pure 0
  | none => do
      IO.eprintln s!"error[LRX-SYN-002]: no explanation is registered for {code}"
      pure 1

private def runKnown : Cli.Command → IO UInt32
  | .check moduleName =>
      if moduleName == "Examples.Counter" then
        match CounterSyntax_check with
        | .ok checked => checkComponent moduleName checked
        | .error error => componentError error
      else if moduleName == "Examples.LeanRxDocs" then
        match LeanRxDocsSyntax_check with
        | .ok checked => checkComponent moduleName checked
        | .error error => componentError error
      else unknownModule moduleName
  | .graph moduleName format =>
      if moduleName == "Examples.Counter" then
        match CounterSyntax_check with
        | .ok checked => graphComponent format checked
        | .error error => componentError error
      else if moduleName == "Examples.LeanRxDocs" then
        match LeanRxDocsSyntax_check with
        | .ok checked => graphComponent format checked
        | .error error => componentError error
      else unknownModule moduleName
  | .build moduleName output =>
      if moduleName == "Examples.Counter" then do
        LeanRxExamples.CounterBuild.generate ⟨output⟩
        IO.println s!"build {moduleName}"
        IO.println s!"  output: {output}"
        IO.println "  publication: atomic versioned bundle"
        IO.println "  result: ok"
        pure 0
      else if moduleName == "Examples.LeanRxDocs" then do
        LeanRxExamples.LeanRxDocsBuild.generate ⟨output⟩
        IO.println s!"build {moduleName}"
        IO.println s!"  output: {output}"
        IO.println "  publication: atomic versioned bundle"
        IO.println "  result: ok"
        pure 0
      else unknownModule moduleName
  | .scaffold output => scaffold output
  | .explain code => explain code
  | .doctor => doctor

def run (args : List String) : IO UInt32 :=
  match Cli.parse args with
  | .ok command => try runKnown command catch error => do
      IO.eprintln error.toString
      pure 1
  | .error error => do
      IO.eprintln s!"error[{error.code}]: {error.message}"
      pure 2

end LeanRx.Cli.Driver
