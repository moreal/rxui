import LeanRx

-- LRX-TYPE-003: the indexed runtime code prevents Int-to-Number remapping.
local instance : LeanRx.RuntimeRep Int where
  runtimeType := .bool
