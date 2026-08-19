import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int .empty
def count : Field S Int := .here
def recurse : EventSpec S := { name := "recurse", update := .dispatch "recurse" }
def eventView : View S := jsx% <button type="button" onClick="recurse"> ["Recurse"]

component RecursiveEventDispatch (schema := S) where {
  state count := ValueSpec.state count (.int 0);
  event recurse := recurse;
  view := eventView;
}
