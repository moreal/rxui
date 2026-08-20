import LeanRx

namespace LeanRxExamples.IssueBrowser

open LeanRx

def spec : LeanRx.IssueBrowser.Spec :=
  LeanRx.IssueBrowser.Spec.create
    "Issue Browser <img src=x onerror=\"globalThis.issueHeadingXss=true\">"

end LeanRxExamples.IssueBrowser
