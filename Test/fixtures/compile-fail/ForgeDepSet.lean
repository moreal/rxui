import LeanRx

abbrev SingleFieldSchema : LeanRx.Schema := .field "only" Int .empty

-- LRX-TYPE-001: raw dependency-set construction is private.
def forged : LeanRx.DepSet SingleFieldSchema := ⟨[99, 0, 0]⟩
