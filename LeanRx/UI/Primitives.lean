import LeanRx.View.Model

namespace LeanRx.UI

/-- A deliberately small, source-owned variant vocabulary for native buttons. -/
inductive ButtonVariant where
  | primary
  | outline
  | ghost

def ButtonVariant.classes : ButtonVariant → String
  | .primary =>
      "inline-flex min-h-11 items-center justify-center rounded-lg bg-primary px-4 text-sm " ++
      "font-medium text-primary-foreground shadow-sm focus-visible:outline-2 " ++
      "focus-visible:outline-offset-2 disabled:pointer-events-none disabled:opacity-50"
  | .outline =>
      "inline-flex min-h-11 items-center justify-center rounded-lg border border-border " ++
      "bg-background px-4 text-sm font-medium text-foreground shadow-sm " ++
      "focus-visible:outline-2 focus-visible:outline-offset-2 disabled:pointer-events-none " ++
      "disabled:opacity-50"
  | .ghost =>
      "inline-flex min-h-11 items-center justify-center rounded-lg px-4 text-sm font-medium " ++
      "text-muted-foreground focus-visible:outline-2 focus-visible:outline-offset-2 " ++
      "disabled:pointer-events-none disabled:opacity-50"

/-- A native button with a sealed event name and project-owned Tailwind classes. -/
def button (label eventName : String) (variant : ButtonVariant := .primary) : View Γ :=
  View.node .button [.text label]
    (attrs := [.className variant.classes, .buttonType .button])
    (events := [{ kind := .click, eventName }])

/-- A semantic callout assembled from the safe static view vocabulary. -/
def callout (title : String) (body : View Γ) : View Γ :=
  View.node .aside [
    View.node .strong [.text title]
      (attrs := [.className "block text-sm font-semibold text-foreground"]),
    body
  ] (attrs := [
    .className
      "rounded-xl border border-border bg-muted/50 px-5 py-4 text-sm leading-7 text-muted-foreground"
  ])

/-- A code surface whose contents always mount through `textContent`. -/
def codeBlock (name : String) (source : RxExpr Γ deps String) : View Γ :=
  View.node .pre [
    View.node .code [.scalarText name source]
      (attrs := [.className "font-mono text-[0.8125rem] leading-6 text-code-foreground"])
  ] (attrs := [
    .className
      "overflow-x-auto rounded-xl bg-code px-5 py-4 text-left shadow-inner"
  ])

end LeanRx.UI
