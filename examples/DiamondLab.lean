import LeanRx

namespace LeanRxExamples.DiamondLab

open LeanRx

abbrev DiamondSchema : Schema :=
  .field "count" Int <| .field "left" Int <| .field "right" Int <|
    .field "total" Int .empty

def count : Field DiamondSchema Int := .here
def left : Field DiamondSchema Int := .there .here
def right : Field DiamondSchema Int := .there (.there .here)
def total : Field DiamondSchema Int := .there (.there (.there .here))

open scoped LeanRxDsl in
/-- Staged with `rx%`; each tree matches the former hand-written constructor form. -/
def leftValue := rx% count + 10
open scoped LeanRxDsl in
def rightValue := rx% count * 2
open scoped LeanRxDsl in
def totalValue := rx% left + right

open scoped LeanRxDsl in
def leftText := rx% s!"Left: {left}"
open scoped LeanRxDsl in
def rightText := rx% s!"Right: {right}"
open scoped LeanRxDsl in
def totalText := rx% s!"Total: {total}"

open scoped LeanRxDsl in
def addTwo : EventSpec DiamondSchema :=
  { name := "addTwo"
    update := .sequence
      (.set count (rx% count + 1))
      (.set count (rx% count + 1)) }

private def click (name : String) : EventBinding := { kind := .click, eventName := name }

def view : View DiamondSchema := View.node .main [
  View.node .h1 [.text "Diamond Lab"],
  View.node .button [.text "Add two"]
    (attrs := [.buttonType .button]) (events := [click "addTwo"]),
  View.node .p [.scalarText "leftText" leftText],
  View.node .p [.scalarText "rightText" rightText],
  View.node .p [.scalarText "totalText" totalText]
] (attrs := [.className "diamond-lab"])

def spec : ComponentSpec DiamondSchema :=
  { name := "DiamondLab"
    values := #[
      ValueSpec.state count (.int 1),
      ValueSpec.computed left leftValue,
      ValueSpec.computed right rightValue,
      ValueSpec.computed total totalValue
    ]
    events := #[addTwo]
    view }

open scoped LeanRxDsl

def syntaxView : View DiamondSchema := jsx% <main class="diamond-lab"> [
  <h1> ["Diamond Lab"],
  <button type="button" onClick="addTwo"> ["Add two"],
  <p> [{"leftText": leftText}],
  <p> [{"rightText": rightText}],
  <p> [{"totalText": totalText}]
]

component DiamondSyntax (schema := DiamondSchema) where {
  state count := ValueSpec.state count (.int 1);
  derived left := ValueSpec.computed left leftValue;
  derived right := ValueSpec.computed right rightValue;
  derived total := ValueSpec.computed total totalValue;
  event addTwo := addTwo;
  view := syntaxView;
}

def allInt : AllInt DiamondSchema := .field (.field (.field (.field .empty)))

def intSpec : IntProgramSpec DiamondSchema :=
  { allInt
    sourceCount := 1
    values := [
      .source count,
      .derived left leftValue,
      .derived right rightValue,
      .derived total totalValue
    ]
    sinks := [.observe "totalObservation" (RxExpr.read total)] }

def abstractTransaction : Abstract.SourceTransaction :=
  [Abstract.SourceWrite.mk 0 2, Abstract.SourceWrite.mk 0 3]

end LeanRxExamples.DiamondLab
