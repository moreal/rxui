import LeanRx

open scoped LeanRxDsl

/- Typed safe views only accept whitelisted static attribute strings. -/
def bad : LeanRx.View .empty := jsx% <div class={"user" ++ "-value"}> []
