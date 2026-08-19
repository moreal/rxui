import LeanRx

namespace LeanRxExamples.DependentTabs

open LeanRx

/-- Public-API dogfood: equal nonempty vectors and a valid initial selection are
checked by Lean before the component reaches any backend phase. -/
def spec : TabsSpec 2 := TabsSpec.createAt
  "Dependent <img src=x onerror=\"globalThis.tabsNameXss=true\"> Tabs"
  #v["Overview", "Details", "<img src=x onerror=\"globalThis.tabsLabelXss=true\">"]
  #v["Shared panel", "Shared panel",
    "<img src=x onerror=\"globalThis.tabsPanelXss=true\">"]
  1 (by decide)

end LeanRxExamples.DependentTabs
