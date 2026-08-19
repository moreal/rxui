import LeanRx

structure HostOnly where
  callback : Nat → Nat

abbrev HostSchema : LeanRx.Schema := .field "host" HostOnly .empty
def host : LeanRx.Field HostSchema HostOnly := .here

-- LRX-TYPE-002: staged reads require browser representation evidence.
def unsupported := LeanRx.RxExpr.read host
