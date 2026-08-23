import examples.TemperatureConverter
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.TemperatureConverterBuild

open LeanRx LeanRx.Form LeanRxExamples.TemperatureConverter

private def expectedCase (scale : TemperatureScale) (raw : String) : IO String :=
  match parseTemperature { scale, raw } with
  | .error error => throw <| IO.userError s!"native temperature case failed: {error.code}"
  | .ok result => pure <|
      "{\"scale\":" ++ Js.Printer.stringLiteral scale.name.toLower ++
      ",\"raw\":" ++ Js.Printer.stringLiteral raw ++
      ",\"converted\":" ++ Js.Printer.stringLiteral (toString result.converted) ++ "}"

private def expectedJson : IO String := do
  let cases ← [
    (.celsius, "100"), (.fahrenheit, "32"), (.celsius, "-40"),
    (.celsius, "-1"),
    (.celsius, "9007199254740993")
  ].mapM fun (scale, raw) => expectedCase scale raw
  pure <| "[" ++ String.intercalate "," cases ++ "]\n"

private def generateChecked (directory : System.FilePath)
    (checked : TemperatureSpec.Checked) : IO Unit := do
  let emitted ← match Backend.Temperature.emit "TemperatureConverter.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"temperature backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"temperature printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "TemperatureConverter.mjs") source
  IO.FS.writeFile (directory / "TemperatureConverter.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "TemperatureConverter.graph.json") (checked.graph.toJson ++ "\n")
  IO.FS.writeFile (directory / "TemperatureConverter.graph.dot") (checked.graph.toDot ++ "\n")
  IO.FS.writeFile (directory / "Temperature.expected.json") (← expectedJson)
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_form_events.mjs")
    (← IO.FS.readFile "runtime/leanrx_form_events.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"temperature component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.TemperatureConverterBuild
