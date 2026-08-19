import LeanRx

def number : LeanRx.RxExpr .empty (LeanRx.DepSet.empty .empty) Int :=
  .literal (.int 1)

def bad : LeanRx.View .empty := LeanRx.View.scalarText "bad" number
