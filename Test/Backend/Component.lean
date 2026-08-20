import LeanRx.Backend.Component
import examples.Counter

namespace LeanRxTest.Backend.Component

open LeanRx LeanRxExamples.Counter

private def verify (checked : CheckedComponent CounterSchema) : IO Unit := do
  let emitted ← match LeanRx.Backend.Component.emit "Counter.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Counter emission failed: {error.code}"
  let readable ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Counter printing failed: {error.code}"
  let compact ← match Js.Printer.module .compact emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"compact Counter printing failed: {error.code}"
  unless readable.contains "from \"./leanrx_dom.mjs\"" &&
      readable.contains "function mount(target)" &&
      readable.contains "function $lrx_event_0(context, ignored)" &&
      readable.contains "if (changed[2])" &&
      readable.contains "setText(refs[2]" &&
      readable.contains "makeDisposer(node_0" && readable.contains ", tx)" do
    throw <| IO.userError s!"Counter output lost direct-DOM component structure:\n{readable}"
  unless ¬readable.contains "currentObserver" && ¬readable.contains "Proxy" &&
      ¬readable.contains "eval(" && ¬readable.contains "Function(" do
    throw <| IO.userError "Counter output introduced a banned runtime mechanism"
  unless emitted.manifest.moduleName == "Counter.mjs" &&
      emitted.manifest.runtimeAbi == 6 &&
      emitted.manifest.exports == #["mount"] &&
      emitted.manifest.stateSlots == #[.int, .int, .string] &&
      emitted.manifest.sourceCount == 1 && emitted.manifest.derivedCount == 2 &&
      emitted.manifest.textSinkCount == 5 && emitted.manifest.eventCount == 4 &&
      emitted.manifest.hostImports == #["./leanrx_dom.mjs", "./leanrx_host.mjs"] &&
      emitted.manifest.features ==
        #["scalar", "events", "transactions", "instrumentation", "trace"] do
    throw <| IO.userError "Counter manifest lost required deterministic metadata"
  let repeated ← match LeanRx.Backend.Component.emit "Counter.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError error.message
  let repeatedCompact ← match Js.Printer.module .compact repeated.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.message
  unless repeatedCompact == compact && repeated.manifest.json == emitted.manifest.json do
    throw <| IO.userError "Counter component output is not deterministic"

def run : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"Counter component rejected: {error.code}"
  | .ok checked => verify checked

end LeanRxTest.Backend.Component
