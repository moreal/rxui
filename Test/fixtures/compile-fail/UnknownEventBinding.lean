import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int .empty
def count : Field S Int := .here
def badView : View S := jsx% <button onClick="missing"> ["Bad"]

component UnknownEventBinding (schema := S) where {
  state count := ValueSpec.state count (.int 0);
  view := badView;
}
