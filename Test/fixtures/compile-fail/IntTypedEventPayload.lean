import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int .empty
def count : Field S Int := .here

component IntTypedEventPayload (schema := S) where {
  state count : Int := 0;
  event setCount (value : Int) := set count value;
  view := jsx% <input onInput={setCount} />;
}
