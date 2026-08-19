import LeanRx

open LeanRx LeanRx.Form

abbrev S : Schema := .field "value" String .empty

def update : TypedEventSpec S String :=
  TypedEventSpec.assign "edit" "value" Field.here

def invalid : StateControlBinding S String :=
  ⟨.keyDown, .value, update⟩
