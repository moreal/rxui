import LeanRx

open LeanRx

abbrev InvalidSchema : Schema :=
  .field "panels" (Vector String 3) <| .field "selected" Nat .empty

def invalid := RxExpr.vectorGet
  (RxExpr.read (.here : Field InvalidSchema (Vector String 3)))
  (RxExpr.read (.there .here : Field InvalidSchema Nat))
