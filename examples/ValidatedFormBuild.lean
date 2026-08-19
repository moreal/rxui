import examples.ValidatedForm
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.ValidatedFormBuild

open LeanRx LeanRx.Form LeanRxExamples.ValidatedForm

private def invalidAgeMessage (age : String) : IO String :=
  match validateForm { name := "Ada", age, accepted := true } with
  | .valid _ => throw <| IO.userError s!"native invalid age fixture was accepted: {age}"
  | .invalid errors =>
      match errors.age with
      | some error => pure error.message
      | none => throw <| IO.userError s!"native invalid age fixture had no age error: {age}"

private def expectedJson : IO String := do
  let lexicalAge ← invalidAgeMessage "1_0"
  let upperAge ← invalidAgeMessage "121"
  match validateForm {
      name := "  <img src=x onerror=\"globalThis.formXss=true\">  "
      age := "42"
      accepted := true
    } with
  | .invalid _ => throw <| IO.userError "native valid form fixture was rejected"
  | .valid value =>
      let command := submit value
      pure <| "{\"name\":" ++ Js.Printer.stringLiteral command.name ++
        ",\"age\":" ++ toString command.age ++
        ",\"invalid\":{\"lexicalAge\":" ++ Js.Printer.stringLiteral lexicalAge ++
        ",\"upperAge\":" ++ Js.Printer.stringLiteral upperAge ++ "}}\n"

private def generateChecked (directory : System.FilePath)
    (checked : ValidatedFormSpec.Checked) : IO Unit := do
  let emitted ← match Backend.ValidatedForm.emit "ValidatedForm.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"validated form backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"validated form printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "ValidatedForm.mjs") source
  IO.FS.writeFile (directory / "ValidatedForm.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "ValidatedForm.graph.json") (checked.graph.toJson ++ "\n")
  IO.FS.writeFile (directory / "ValidatedForm.graph.dot") (checked.graph.toDot ++ "\n")
  IO.FS.writeFile (directory / "ValidatedForm.expected.json") (← expectedJson)
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"validated form invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.ValidatedFormBuild
