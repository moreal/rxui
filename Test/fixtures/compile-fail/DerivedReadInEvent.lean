import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int <| .field "doubled" Int .empty
def count : Field S Int := .here
def doubled : Field S Int := .there .here
def doubledValue := RxExpr.binary .intMul
  (RxExpr.read count) (RxExpr.literal (.int 2))
def badEvent : EventSpec S :=
  { name := "bad"
    update := .set count <| RxExpr.binary .intAdd
      (RxExpr.read doubled) (RxExpr.literal (.int 1)) }
def eventView : View S := jsx% <button type="button" onClick="bad"> ["Bad"]

component DerivedReadInEvent (schema := S) where {
  state count := ValueSpec.state count (.int 1);
  derived doubled := ValueSpec.computed doubled doubledValue;
  event bad := badEvent;
  view := eventView;
}
