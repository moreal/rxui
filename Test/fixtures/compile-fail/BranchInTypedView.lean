import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

/- The sealed two-branch cell lowers only inside region row templates
(ADR-0047); a component view rejects it. -/
def bad : View S := jsx% <main> [
  {if mode == "view"
    then <span> ["view"]
    else <span> ["edit"]}
]
