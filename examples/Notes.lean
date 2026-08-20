import LeanRx

namespace LeanRxExamples.Notes

open LeanRx

def spec : LeanRx.Notes.Spec :=
  LeanRx.Notes.Spec.create "Notes <img src=x onerror=\"globalThis.notesXss=true\">"

end LeanRxExamples.Notes
