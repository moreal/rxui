import LeanRx

open LeanRx LeanRx.Effect

def mismatched : Except Error (ForeignPort String String) :=
  ForeignPort.createStructured "mismatch" (.record "NotString") (.runtime .bool)
    .sync .none #[] "trust" "security" .ok
