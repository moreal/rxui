import LeanRx

attribute [-instance] LeanRx.instRuntimeEqInt

abbrev S : LeanRx.Schema := .field "count" Int .empty
def count : LeanRx.Field S Int := .here

def bad : LeanRx.ValueSpec S := LeanRx.ValueSpec.state count (.int 0)
