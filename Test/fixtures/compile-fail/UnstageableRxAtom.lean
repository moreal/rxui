import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int .empty

def count : Field S Int := .here

/- Staging an unsupported host value must fail with the stable rx% diagnostic. -/
def bad := rx% count + ([1, 2] : List Int)
