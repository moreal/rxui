import LeanRx

namespace LeanRxExamples.DependentTabs

open LeanRx

/-- Public-API dogfood: equal nonempty vectors and a valid initial selection are
checked by Lean before the component reaches any backend phase. -/
def spec : TabsSpec 2 := TabsSpec.create "Dependent Tabs"
  #v["Overview", "Details", "History"]
  #v["Overview panel", "Details panel", "History panel"]
  ⟨1, by decide⟩

end LeanRxExamples.DependentTabs
