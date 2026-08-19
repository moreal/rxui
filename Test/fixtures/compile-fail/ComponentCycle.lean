import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev CycleSchema : Schema := .field "a" Int <| .field "b" Int .empty
def a : Field CycleSchema Int := .here
def b : Field CycleSchema Int := .there .here
def aValue := RxExpr.read b
def bValue := RxExpr.read a
def cycleView : View CycleSchema := jsx% <p> ["cycle"]

component Cycle (schema := CycleSchema) where {
  derived a := ValueSpec.computed a aValue;
  derived b := ValueSpec.computed b bValue;
  view := cycleView;
}
