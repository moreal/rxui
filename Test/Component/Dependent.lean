import LeanRx.Component.Tabs

namespace LeanRxTest.Component.Dependent

open LeanRx

def oneTab : TabsSpec 0 :=
  TabsSpec.create "OneTab" #v["Only"] #v["Only panel"]

def mappedLabels : Vector String 3 :=
  Vector.ofFn fun index => "Tab " ++ toString (index.val + 1)

def threeTabs : TabsSpec 2 :=
  TabsSpec.createAt "ThreeTabs" mappedLabels
    #v["First panel", "Second panel", "Third panel"] 1 (by decide)

private def checkOne (one : TabsSpec.Checked 0) : IO Unit := do
  unless one.spec.props.count == 1 && one.spec.initialSelected.val == 0 do
    throw <| IO.userError "one-tab dependent construction lost nonempty selection"

private def checkThree (three : TabsSpec.Checked 2) : IO Unit := do
  unless (3 : Fin 3).val == 0 do
    throw <| IO.userError "pinned Lean Fin literal normalization premise changed"
  unless three.spec.props.labels.value.toList == ["Tab 1", "Tab 2", "Tab 3"] do
    throw <| IO.userError "mapping dependent labels with indices changed"
  unless three.spec.props.panels.value.get three.spec.initialSelected == "Second panel" do
    throw <| IO.userError "safe initial panel selection changed"
  unless three.event.payloadType == RuntimeTypeId.fin 3 && three.event.target.index == 0 do
    throw <| IO.userError "typed event payload drifted from its finite state target"
  unless three.graph.graph.nodes.map (·.valueType) ==
      #[RuntimeTypeId.fin 3, RuntimeTypeId.string] do
    throw <| IO.userError "dependent component graph lost runtime type identities"
  unless three.erasure.erased == [ReactiveIR.StaticEvidence.vectorLength 3,
      ReactiveIR.StaticEvidence.finBound 3] &&
      three.erasure.inspections.isEmpty do
    throw <| IO.userError "dependent component did not pass proof-erasure analysis"

def run : IO Unit := do
  match oneTab.check with
  | .ok checked => checkOne checked
  | .error error => throw <| IO.userError s!"one-tab component failed: {error.code}"
  match threeTabs.check with
  | .ok checked => checkThree checked
  | .error error => throw <| IO.userError s!"three-tab component failed: {error.code}"

end LeanRxTest.Component.Dependent
