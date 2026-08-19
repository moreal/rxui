import LeanRx

namespace LeanRxExamples.Counter

open LeanRx

abbrev CounterSchema : Schema :=
  .field "count" Int <| .field "doubled" Int <| .field "parity" String .empty

def count : Field CounterSchema Int := .here
def doubledField : Field CounterSchema Int := .there .here
def parityField : Field CounterSchema String := .there (.there .here)

def doubled := RxExpr.binary .intMul (RxExpr.read count) (RxExpr.literal (.int 2))

def parity := RxExpr.ifThenElse
  (RxExpr.binary .intEq
    (RxExpr.binary .intMod (RxExpr.read count) (RxExpr.literal (.int 2)))
    (RxExpr.literal (.int 0)))
  (RxExpr.literal (.string "even"))
  (RxExpr.literal (.string "odd"))

def countText := RxExpr.binary .stringAppend (RxExpr.literal (.string "Count: "))
  (RxExpr.unary .intToString (RxExpr.read count))

def doubledText := RxExpr.binary .stringAppend (RxExpr.literal (.string "Doubled: "))
  (RxExpr.unary .intToString (RxExpr.read doubledField))

def parityText := RxExpr.binary .stringAppend (RxExpr.literal (.string "Parity: "))
  (RxExpr.read parityField)

def hostileText := RxExpr.literal (Γ := CounterSchema) <|
  .string "<img src=x onerror=\"globalThis.leanrxXss=true\">"

def stableText := RxExpr.ifThenElse
  (RxExpr.binary .intEq (RxExpr.read count) (RxExpr.read count))
  (RxExpr.literal (.string "Stable"))
  (RxExpr.literal (.string "Stable"))

def increment : EventSpec CounterSchema :=
  { name := "increment"
    update := .set count <| RxExpr.binary .intAdd
      (RxExpr.read count) (RxExpr.literal (.int 1)) }

def addTwo : EventSpec CounterSchema :=
  { name := "addTwo"
    update := .sequence
      (.set count <| RxExpr.binary .intAdd
        (RxExpr.read count) (RxExpr.literal (.int 1)))
      (.set count <| RxExpr.binary .intAdd
        (RxExpr.read count) (RxExpr.literal (.int 1))) }

def nestedAddTwo : EventSpec CounterSchema :=
  { name := "nestedAddTwo"
    update := .sequence (.dispatch "increment") (.dispatch "increment") }

def roundTrip : EventSpec CounterSchema :=
  { name := "roundTrip"
    update := .sequence
      (.set count <| RxExpr.binary .intAdd
        (RxExpr.read count) (RxExpr.literal (.int 1)))
      (.set count <| RxExpr.binary .intSub
        (RxExpr.read count) (RxExpr.literal (.int 1))) }

private def click (name : String) : EventBinding := { kind := .click, eventName := name }

/-- Counter's explicit public view; syntax sugar is layered over this checked term. -/
def view : View CounterSchema := View.node .main [
  View.node .h1 [.text "Counter"],
  View.node .button [.text "Increment"]
    (attrs := [.buttonType .button]) (events := [click "increment"]),
  View.node .button [.text "Add two"]
    (attrs := [.buttonType .button]) (events := [click "addTwo"]),
  View.node .button [.text "Nested add two"]
    (attrs := [.buttonType .button]) (events := [click "nestedAddTwo"]),
  View.node .button [.text "Round trip"]
    (attrs := [.buttonType .button]) (events := [click "roundTrip"]),
  View.node .p [.scalarText "countText" countText],
  View.node .p [.scalarText "doubledText" doubledText],
  View.node .p [.scalarText "parityText" parityText],
  View.node .p [.scalarText "stableText" stableText],
  View.node .p [.scalarText "hostileText" hostileText]
] (attrs := [.className "counter"])

/-- Counter uses only the public explicit M4 component API. -/
def spec : ComponentSpec CounterSchema :=
  { name := "Counter"
    values := #[
      ValueSpec.state count (.int 1),
      ValueSpec.computed doubledField doubled,
      ValueSpec.computed parityField parity
    ]
    events := #[increment, addTwo, nestedAddTwo, roundTrip]
    view }

open scoped LeanRxDsl

/-- Lean-friendly M4 JSX surface: balanced `[...]` children avoid a custom
closing-tag parser while preserving HTML-like tags and whitelisted attributes. -/
def syntaxView : View CounterSchema := jsx% <main class="counter"> [
  <h1> ["Counter"],
  <button type="button" onClick="increment"> ["Increment"],
  <button type="button" onClick="addTwo"> ["Add two"],
  <button type="button" onClick="nestedAddTwo"> ["Nested add two"],
  <button type="button" onClick="roundTrip"> ["Round trip"],
  <p> [{"countText": countText}],
  <p> [{"doubledText": doubledText}],
  <p> [{"parityText": parityText}],
  <p> [{"stableText": stableText}],
  <p> [{"hostileText": hostileText}]
]

component CounterSyntax (schema := CounterSchema) where {
  state count := ValueSpec.state count (.int 1);
  derived doubled := ValueSpec.computed doubledField doubled;
  derived parity := ValueSpec.computed parityField parity;
  event increment := increment;
  event addTwo := addTwo;
  event nestedAddTwo := nestedAddTwo;
  event roundTrip := roundTrip;
  view := syntaxView;
}

end LeanRxExamples.Counter
