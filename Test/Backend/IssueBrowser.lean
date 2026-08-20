import LeanRx.Backend.IssueBrowser
import LeanRx.Backend.JsPrinter

namespace LeanRxTest.Backend.IssueBrowser

open LeanRx LeanRx.IssueBrowser

private def assertTrue (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let checked ← match (Spec.create "Issue Browser").check with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError error.message
  let emitted ← match Backend.IssueBrowser.emit "IssueBrowser.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"{error.code}: {error.message}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"{error.code}: {error.message}"
  assertTrue (source.contains "decodeIssueResponse" && source.contains "http" &&
    source.contains "createKeyedRegion" && source.contains "makeEffectDisposer")
    "Issue Browser backend omitted its checked HTTP/resource lifecycle"
  assertTrue (emitted.manifest.sourceCount == 4 && emitted.manifest.eventCount == 4 &&
    emitted.manifest.features.contains "foreign:decodeIssuePage" &&
    emitted.manifest.ports == #[Backend.PortManifest.ofForeign checked.decoder])
    "Issue Browser manifest drifted"

end LeanRxTest.Backend.IssueBrowser
