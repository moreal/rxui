import LeanRx.Backend.JsPrinter
import LeanRx.Backend.Todo

namespace LeanRxTest.Backend.Todo

open LeanRx LeanRx.Todo

def run : IO Unit := do
  let checked ← match (Spec.create "TodoMVC").check with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError s!"Todo spec failed: {error.code}"
  let emitted ← match Backend.Todo.emit "TodoMVC.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Todo backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Todo printer failed: {error.code}"
  unless source.contains "createKeyedRegion" && source.contains "createConditionalRegion" &&
      source.contains "createPositionalRegion" && source.contains "listenDelegated" &&
      source.contains "for (const todo of state[0])" &&
      source.contains "data-lrx-action" && source.contains "data-lrx-key" &&
      ¬source.contains "innerHTML" && ¬source.contains "currentObserver" &&
      ¬source.contains "new Proxy" do
    throw <| IO.userError "Todo dynamic-region lowering changed"
  unless emitted.manifest.runtimeAbi == 5 && emitted.manifest.stateSlots == #[
      .list (.record "TodoItem"), .nat, .string, .int, .string, .string] &&
      emitted.manifest.sourceCount == 6 && emitted.manifest.derivedCount == 0 &&
      emitted.manifest.textSinkCount == 2 && emitted.manifest.eventCount == 10 &&
      emitted.manifest.hostImports ==
        #["./leanrx_dom.mjs", "./leanrx_region.mjs", "./leanrx_host.mjs"] do
    throw <| IO.userError "Todo dynamic manifest changed"

end LeanRxTest.Backend.Todo
