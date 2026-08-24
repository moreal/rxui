import LeanRx

namespace LeanRxTest.Elab.ViewSurface

open LeanRx
open scoped LeanRxDsl

private abbrev DashboardSchema : Schema :=
  .field "count" Int <| .field "metricText" String .empty

private def countField : Field DashboardSchema Int := .here
private def metricField : Field DashboardSchema String := .there .here

private def metricValue := rx% s!"Count: {countField}"

/-- A nested typed view component whose prop is a staged expression. -/
private def Metric (value : RxExpr DashboardSchema deps String) :
    View DashboardSchema :=
  jsx% <p role="status"> [ {"metric": value} ]

private def bump : EventSpec DashboardSchema :=
  { name := "bump", update := .set countField (rx% countField + 1) }

private def bumpTwice : EventSpec DashboardSchema :=
  { name := "bumpTwice", update := .set countField (rx% countField + 2) }

/-- Expanded whitelist tags/attributes plus a double-click binding and a
nested component in child position, all in the schema-typed view. -/
private def dashboard : View DashboardSchema :=
  jsx% <main class="dashboard"> [
    <header> [ <h2> ["Stats"] ],
    <nav> [
      <button type="button" onClick="bump" onDblClick="bumpTwice"> ["Bump"]
    ],
    <Metric value={metricValue}/>,
    <ul> [ <li> [ <strong> ["one"] ], <li> [ <em> ["two"] ] ],
    <input placeholder="Type here" ariaLabel="Entry"/>,
    <footer> [ <label> ["done"] ]
  ]

private def spec : ComponentSpec DashboardSchema :=
  { name := "Dashboard"
    values := #[
      ValueSpec.state countField (.int 0),
      ValueSpec.computed metricField metricValue
    ]
    events := #[bump, bumpTwice]
    «view» := dashboard }

/-- The expanded typed surface must validate and lower end to end. -/
def run : IO Unit := do
  match spec.check with
  | .error error => throw <| IO.userError s!"expanded typed view rejected: {error.code}"
  | .ok checked =>
      unless checked.view.events.map (fun mounted => mounted.binding.kind.name) ==
          ["click", "dblclick"] do
        throw <| IO.userError "expanded typed view lost its event kinds"
      unless checked.view.textSinks.map (·.name) == ["metric"] do
        throw <| IO.userError "nested component sink did not survive lowering"
      match Backend.Component.emit "Dashboard.mjs" checked with
      | .error error =>
          throw <| IO.userError s!"expanded typed view failed to lower: {error.code}"
      | .ok emitted =>
          unless emitted.manifest.eventCount == 2 do
            throw <| IO.userError "expanded typed view manifest lost an event"

end LeanRxTest.Elab.ViewSurface
