import LeanRx

abbrev S : LeanRx.Schema := .field "count" Int .empty
def count : LeanRx.Field S Int := .here
def update : LeanRx.Update S := .set count (LeanRx.RxExpr.literal (.int 1))

def bad : LeanRx.ValueSpec S := LeanRx.ValueSpec.computed count update
