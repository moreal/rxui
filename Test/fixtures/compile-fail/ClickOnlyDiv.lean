import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int .empty
def count : Field S Int := .here
def increment : EventSpec S :=
  { name := "increment", update := .set count (RxExpr.literal (.int 1)) }
def badView : View S := jsx% <div onClick="increment"> ["Bad"]

component ClickOnlyDiv (schema := S) where {
  state count := ValueSpec.state count (.int 0);
  event increment := increment;
  view := badView;
}
