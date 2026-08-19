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

def increment : EventSpec CounterSchema :=
  { name := "increment"
    update := .set count <| RxExpr.binary .intAdd
      (RxExpr.read count) (RxExpr.literal (.int 1)) }

def addTwo : EventSpec CounterSchema :=
  { name := "addTwo"
    update := .set count <| RxExpr.binary .intAdd
      (RxExpr.read count) (RxExpr.literal (.int 2)) }

private def click (name : String) : EventBinding := { kind := .click, eventName := name }

/-- Counter's explicit public view; syntax sugar is layered over this checked term. -/
def view : View CounterSchema := View.node .main [
  View.node .h1 [.text "Counter"],
  View.node .button [.text "Increment"]
    (attrs := [.buttonType .button]) (events := [click "increment"]),
  View.node .button [.text "Add two"]
    (attrs := [.buttonType .button]) (events := [click "addTwo"]),
  View.node .p [.scalarText "countText" countText],
  View.node .p [.scalarText "doubledText" doubledText],
  View.node .p [.scalarText "parityText" parityText]
] (attrs := [.className "counter"])

/-- Counter uses only the public explicit M4 component API. -/
def spec : ComponentSpec CounterSchema :=
  { name := "Counter"
    values := #[
      ValueSpec.state count (.int 1),
      ValueSpec.computed doubledField doubled,
      ValueSpec.computed parityField parity
    ]
    events := #[increment, addTwo]
    view }

open scoped LeanRxDsl

/-- Lean-friendly M4 JSX surface: balanced `[...]` children avoid a custom
closing-tag parser while preserving HTML-like tags and whitelisted attributes. -/
def syntaxView : View CounterSchema := jsx% <main class="counter"> [
  <h1> ["Counter"],
  <button type="button" onClick="increment"> ["Increment"],
  <button type="button" onClick="addTwo"> ["Add two"],
  <p> [{"countText": countText}],
  <p> [{"doubledText": doubledText}],
  <p> [{"parityText": parityText}]
]

component CounterSyntax (schema := CounterSchema) where {
  state count := ValueSpec.state count (.int 1);
  derived doubled := ValueSpec.computed doubledField doubled;
  derived parity := ValueSpec.computed parityField parity;
  event increment := increment;
  event addTwo := addTwo;
  view := syntaxView;
}

end LeanRxExamples.Counter
