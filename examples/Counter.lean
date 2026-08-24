import LeanRx

namespace LeanRxExamples.Counter

open LeanRx

abbrev CounterSchema : Schema :=
  .field "count" Int <| .field "doubled" Int <| .field "parity" String .empty

def count : Field CounterSchema Int := .here
def doubledField : Field CounterSchema Int := .there .here
def parityField : Field CounterSchema String := .there (.there .here)

open scoped LeanRxDsl in
/-- Staged expressions use the `rx%` surface; each staged tree is identical to
its previous hand-written `RxExpr` constructor form. -/
def doubled := rx% count * 2

open scoped LeanRxDsl in
def parity := rx% if count % 2 == 0 then "even" else "odd"

open scoped LeanRxDsl in
def countText := rx% s!"Count: {count}"

open scoped LeanRxDsl in
def doubledText := rx% s!"Doubled: {doubledField}"

open scoped LeanRxDsl in
def parityText := rx% s!"Parity: {parityField}"

open scoped LeanRxDsl in
def hostileText : RxExpr CounterSchema (DepSet.empty CounterSchema) String :=
  rx% "<img src=x onerror=\"globalThis.leanrxXss=true\">"

open scoped LeanRxDsl in
def stableText := rx% if count == count then "Stable" else "Stable"

open scoped LeanRxDsl in
def increment : EventSpec CounterSchema :=
  { name := "increment"
    update := .set count (rx% count + 1) }

open scoped LeanRxDsl in
def addTwo : EventSpec CounterSchema :=
  { name := "addTwo"
    update := .sequence
      (.set count (rx% count + 1))
      (.set count (rx% count + 1)) }

def nestedAddTwo : EventSpec CounterSchema :=
  { name := "nestedAddTwo"
    update := .sequence (.dispatch "increment") (.dispatch "increment") }

open scoped LeanRxDsl in
def roundTrip : EventSpec CounterSchema :=
  { name := "roundTrip"
    update := .sequence
      (.set count (rx% count + 1))
      (.set count (rx% count - 1)) }

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
