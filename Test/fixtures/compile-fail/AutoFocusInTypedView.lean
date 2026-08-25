import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

/- The sealed autoFocus marker is row-branch vocabulary (ADR-0048); the
component view's static inputs reject it. -/
def bad : View S := jsx% <main> [
  <input ariaLabel="Editor" autoFocus/>
]
