import LeanRx

open LeanRx LeanRx.Form

def invalid : TemperatureSpec.UpdatePlan :=
  ⟨.textInput (TypedEventSpec.assign "edit" "value" celsiusField),
    .celsius, celsiusField, .value⟩
