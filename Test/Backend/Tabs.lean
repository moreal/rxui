import LeanRx.Backend.Tabs
import LeanRx.Backend.JsPrinter
import Test.Component.Dependent

namespace LeanRxTest.Backend.Tabs

open LeanRx LeanRxTest.Component.Dependent

def run : IO Unit := do
  match threeTabs.check with
  | .error error => throw <| IO.userError s!"Tabs model failed: {error.code}"
  | .ok checked =>
    match Backend.Tabs.emit "DependentTabs.mjs" checked with
    | .error error => throw <| IO.userError s!"Tabs backend failed: {error.code}"
    | .ok emitted =>
      let source ← match Js.Printer.module .readable emitted.module with
        | .ok source => pure source
        | .error error => throw <| IO.userError s!"Tabs printer failed: {error.code}"
      unless source.contains "return panels[selected];" &&
          source.contains "function $lrx_select(state, context, index)" &&
          source.contains "if (!(state[0] === index))" &&
          source.contains "setText(context[0], next)" &&
          source.contains "createText(\"Third panel\")" == false &&
          ¬source.contains "Nat.zero_lt_succ" && ¬source.contains "proof" do
        throw <| IO.userError s!"dependent Tabs lowering changed:\n{source}"
      unless emitted.manifest.runtimeAbi == 14 &&
          emitted.manifest.stateSlots == #[Backend.ManifestTypeId.fin 3] &&
          emitted.manifest.sourceCount == 1 && emitted.manifest.derivedCount == 0 &&
          emitted.manifest.textSinkCount == 1 && emitted.manifest.eventCount == 1 &&
          emitted.manifest.features == #["dependent", "immutable-props", "typed-events",
            "proof-erasure", "direct-dom", "actual-change", "instrumentation", "trace"] do
        throw <| IO.userError "dependent Tabs manifest changed"

end LeanRxTest.Backend.Tabs
