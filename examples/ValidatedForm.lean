import LeanRx

namespace LeanRxExamples.ValidatedForm

open LeanRx.Form

def spec : ValidatedFormSpec := ValidatedFormSpec.create "Validated Form"
  { name := "", age := "17", accepted := false }

end LeanRxExamples.ValidatedForm
