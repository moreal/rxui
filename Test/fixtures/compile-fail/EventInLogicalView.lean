import LeanRx

open scoped LeanRxDsl

/- The logical reference model carries no event bindings. -/
def bad : LeanRx.Region.LogicalNode := jsx% <button onClick="fire"> ["Fire"]
