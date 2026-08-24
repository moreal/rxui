import LeanRx

open scoped LeanRxDsl

/- Unknown elements stay outside the closed whitelist in both view targets. -/
def bad : LeanRx.View .empty := jsx% <script> ["alert(1)"]
