import LeanRx.Component.Model

namespace LeanRxTest.CounterSpec

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

def view : View CounterSchema := View.node .main [
  View.node .button [.text "Increment"]
    (attrs := [.buttonType .button]) (events := [click "increment"]),
  View.node .button [.text "Add two"]
    (attrs := [.buttonType .button]) (events := [click "addTwo"]),
  View.node .p [.scalarText "countText" countText],
  View.node .p [.scalarText "doubledText" doubledText],
  View.node .p [.scalarText "parityText" parityText]
] (attrs := [.className "counter"])

def spec : ComponentSpec CounterSchema :=
  { name := "Counter"
    values := #[
      ValueSpec.state count (.int 1),
      ValueSpec.computed doubledField doubled,
      ValueSpec.computed parityField parity
    ]
    events := #[increment, addTwo]
    view }

end LeanRxTest.CounterSpec
