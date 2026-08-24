import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "loud" Bool .empty
def loud : Field S Bool := .here

component PayloadClassMismatch (schema := S) where {
  state loud : Bool := false;
  event toggleLoud (checked : Bool) := set loud checked;
  view := jsx% <input onInput={toggleLoud} />;
}
