import LeanRx.Form.Validation

namespace LeanRxTest.Form.Validation

open LeanRx.Form

def run : IO Unit := do
  match Parser.signedInt.run "-12" with
  | .ok value =>
      unless value == -12 do
        throw <| IO.userError "signed integer parser changed a valid negative value"
  | .error _ => throw <| IO.userError "signed integer parser rejected a valid negative value"
  match Parser.signedInt.run "1.5" with
  | .ok _ => throw <| IO.userError "signed integer parser accepted a decimal"
  | .error error =>
      unless error.code == "LRX-TYPE-201" do
        throw <| IO.userError "signed integer parser returned the wrong diagnostic"
  for input in ["1_000", "-0_1", "_1", "1_", "1__0", "+1", ""] do
    match Parser.signedInt.run input with
    | .ok _ => throw <| IO.userError s!"signed integer parser accepted closed-grammar input {repr input}"
    | .error error =>
        unless error.code == "LRX-TYPE-201" do
          throw <| IO.userError "signed integer parser returned the wrong closed-grammar diagnostic"
  match Parser.natural.run "42" with
  | .ok value =>
      unless value == 42 do
        throw <| IO.userError "natural parser changed a valid value"
  | .error _ => throw <| IO.userError "natural parser rejected a valid value"
  for input in ["1_000", "_1", "1_", "1__0", "-1", "+1", ""] do
    match Parser.natural.run input with
    | .ok _ => throw <| IO.userError s!"natural parser accepted closed-grammar input {repr input}"
    | .error error =>
        unless error.code == "LRX-TYPE-202" do
          throw <| IO.userError "natural parser returned the wrong closed-grammar diagnostic"
  match parseTemperature { scale := .celsius, raw := "100" } with
  | .ok result =>
      unless result.edited == .celsius && result.parsed == 100 && result.converted == 212 do
        throw <| IO.userError "Celsius conversion changed"
  | .error _ => throw <| IO.userError "valid Celsius input was rejected"
  match parseTemperature { scale := .fahrenheit, raw := "32" } with
  | .ok result =>
      unless result.edited == .fahrenheit && result.parsed == 32 && result.converted == 0 do
        throw <| IO.userError "Fahrenheit conversion changed"
  | .error _ => throw <| IO.userError "valid Fahrenheit input was rejected"
  match validateForm { name := "  Ada  ", age := "42", accepted := true } with
  | .invalid _ => throw <| IO.userError "valid form data was rejected"
  | .valid value =>
      let command := submit value
      unless command.name == "Ada" && command.age == 42 do
        throw <| IO.userError "validated submit payload changed"
  match validateForm { name := "  ", age := "17", accepted := false } with
  | .valid _ => throw <| IO.userError "invalid form data reached a submit capability"
  | .invalid errors =>
      unless errors.name.map (·.code) == some "LRX-TYPE-203" &&
          errors.age.map (·.code) == some "LRX-TYPE-204" &&
          errors.accepted.map (·.code) == some "LRX-TYPE-207" do
        throw <| IO.userError "form validation did not accumulate all errors"

end LeanRxTest.Form.Validation
