import LeanRx

open scoped LeanRxDsl

/- Keyed list children lower onto the logical region IR only. -/
def bad : LeanRx.View .empty := jsx% <ul> [
  for item in ([] : List Nat) key item => <li> []
]
