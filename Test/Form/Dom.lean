import LeanRx.Form.Dom

namespace LeanRxTest.Form.Dom

open LeanRx.Form

def run : IO Unit := do
  unless DomProperty.value.name == "value" && DomProperty.checked.name == "checked" &&
      DomProperty.disabled.name == "disabled" do
    throw <| IO.userError "closed form property names changed"
  unless ControlEvent.input.name == "input" && ControlEvent.input.payloadKind == .text &&
      ControlEvent.change.name == "change" && ControlEvent.change.payloadKind == .text &&
      ControlEvent.checkedChange.name == "change" &&
      ControlEvent.checkedChange.payloadKind == .checked &&
      ControlEvent.submit.name == "submit" && ControlEvent.submit.payloadKind == .none &&
      ControlEvent.keyDown.name == "keydown" && ControlEvent.keyDown.payloadKind == .key &&
      ControlEvent.focus.name == "focus" && ControlEvent.blur.name == "blur" do
    throw <| IO.userError "closed form event payload contract changed"

end LeanRxTest.Form.Dom
