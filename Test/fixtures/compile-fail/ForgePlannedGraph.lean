import LeanRx

def forged : LeanRx.PlannedGraph :=
  { graph := ⟨#[]⟩
    schedule := ⟨#[]⟩
    valid := by decide }
