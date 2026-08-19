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
  match validateForm { name := "  Ada  ", age := "42" } with
  | .invalid _ => throw <| IO.userError "valid form data was rejected"
  | .valid value =>
      unless submit value == { name := "Ada", age := 42 } do
        throw <| IO.userError "validated submit payload changed"
  match validateForm { name := "  ", age := "17" } with
  | .valid _ => throw <| IO.userError "invalid form data reached a submit capability"
  | .invalid errors =>
      unless errors.name.map (·.code) == some "LRX-TYPE-203" &&
          errors.age.map (·.code) == some "LRX-TYPE-204" do
        throw <| IO.userError "form validation did not accumulate both errors"

end LeanRxTest.Form.Validation
