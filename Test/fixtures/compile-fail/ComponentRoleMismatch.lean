import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "value" Int .empty
def value : Field S Int := .here
def badView : View S := jsx% <p> ["Bad"]

component RoleMismatch (schema := S) where {
  state claimedState := ValueSpec.computed value (RxExpr.literal (.int 1));
  view := badView;
}
