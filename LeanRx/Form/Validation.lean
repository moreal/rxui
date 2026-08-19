namespace LeanRx.Form

/-- Stable user-facing parser/validator failure. Parsing is pure and never
throws; browser adapters render these values explicitly. -/
structure ValidationError where
  code : String
  message : String
deriving Repr, BEq

structure Parser (α : Type) where
  run : String → Except ValidationError α

namespace Parser

def map (parser : Parser α) (f : α → β) : Parser β where
  run input := parser.run input |>.map f

def andThen (parser : Parser α) (next : α → Except ValidationError β) : Parser β where
  run input := parser.run input >>= next

/-- ASCII signed integer parser matching the M7 browser grammar. -/
def signedInt : Parser Int where
  run input := match input.toInt? with
    | some value => .ok value
    | none => .error {
        code := "LRX-TYPE-201"
        message := "enter an integer using optional '-' and ASCII digits"
      }

def natural : Parser Nat where
  run input := match input.toNat? with
    | some value => .ok value
    | none => .error {
        code := "LRX-TYPE-202"
        message := "enter a non-negative integer using ASCII digits"
      }

end Parser

structure Validator (α β : Type) where
  run : α → Except ValidationError β

namespace Validator

def map (validator : Validator α β) (f : β → γ) : Validator α γ where
  run value := validator.run value |>.map f

def after (parser : Parser α) (validator : Validator α β) : Parser β :=
  parser.andThen validator.run

end Validator

structure NonEmptyString where
  private mk ::
  value : String
deriving Repr, BEq

namespace NonEmptyString

def validator : Validator String NonEmptyString where
  run value :=
    let trimmed := value.trimAscii.toString
    if trimmed.isEmpty then
      .error { code := "LRX-TYPE-203", message := "name must not be empty" }
    else .ok ⟨trimmed⟩

end NonEmptyString

structure BoundedNat (minimum maximum : Nat) where
  private mk ::
  value : Nat
  lower : minimum ≤ value
  upper : value ≤ maximum

namespace BoundedNat

def validator (minimum maximum : Nat) : Validator Nat (BoundedNat minimum maximum) where
  run value :=
    if lower : minimum ≤ value then
      if upper : value ≤ maximum then .ok ⟨value, lower, upper⟩
      else .error {
        code := "LRX-TYPE-205"
        message := s!"value must be at most {maximum}"
      }
    else .error {
      code := "LRX-TYPE-204"
      message := s!"value must be at least {minimum}"
    }

end BoundedNat

def boundedNatural (minimum maximum : Nat) : Parser (BoundedNat minimum maximum) :=
  Validator.after Parser.natural (BoundedNat.validator minimum maximum)

structure AcceptedTerms where
  private mk ::

namespace AcceptedTerms

def validator : Validator Bool AcceptedTerms where
  run accepted :=
    if accepted then .ok ⟨⟩
    else .error { code := "LRX-TYPE-207", message := "terms must be accepted" }

end AcceptedTerms

inductive TemperatureScale where
  | celsius
  | fahrenheit
deriving Repr, BEq, DecidableEq

def TemperatureScale.name : TemperatureScale → String
  | .celsius => "Celsius"
  | .fahrenheit => "Fahrenheit"

/-- Integer conversion deliberately uses truncating division in both Lean and
generated BigInt JavaScript. The text parser remains explicit about its domain. -/
def convertTemperature : TemperatureScale → Int → Int
  | .celsius, value => Int.tdiv (value * 9) 5 + 32
  | .fahrenheit, value => Int.tdiv ((value - 32) * 5) 9

structure TemperatureEdit where
  scale : TemperatureScale
  raw : String
deriving Repr, BEq

structure TemperatureResult where
  edited : TemperatureScale
  parsed : Int
  converted : Int
deriving Repr, BEq

def parseTemperature (edit : TemperatureEdit) : Except ValidationError TemperatureResult := do
  let parsed ← Parser.signedInt.run edit.raw
  pure { edited := edit.scale, parsed, converted := convertTemperature edit.scale parsed }

structure RawForm where
  name : String
  age : String
  accepted : Bool := false
deriving Repr, BEq

structure ValidatedForm where
  private mk ::
  name : NonEmptyString
  age : BoundedNat 18 120
  accepted : AcceptedTerms

structure FormErrors where
  name : Option ValidationError := none
  age : Option ValidationError := none
  accepted : Option ValidationError := none
deriving Repr, BEq

inductive FormValidation where
  | invalid (errors : FormErrors)
  | valid (value : ValidatedForm)

private def exceptError : Except ε α → Option ε
  | .ok _ => none
  | .error error => some error

def validateForm (raw : RawForm) : FormValidation :=
  let name := NonEmptyString.validator.run raw.name
  let age := boundedNatural 18 120 |>.run raw.age
  let accepted := AcceptedTerms.validator.run raw.accepted
  match name, age, accepted with
  | .ok name, .ok age, .ok accepted => .valid ⟨name, age, accepted⟩
  | name, age, accepted => .invalid {
      name := exceptError name
      age := exceptError age
      accepted := exceptError accepted
    }

/-- Explicit fake command boundary. Only a successfully validated value can
construct its payload; raw strings have no submission API. -/
structure FakeSubmitCommand where
  private mk ::
  name : String
  age : Nat
deriving Repr, BEq

def submit (value : ValidatedForm) : FakeSubmitCommand :=
  { name := value.name.value, age := value.age.value }

end LeanRx.Form
