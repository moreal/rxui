import LeanRx.UI.Primitives

namespace LeanRx.Docs

/-- Static navigation metadata kept beside a documentation page's reactive copy. -/
structure Page where
  slug : String
  label : String
  eventName : String

private def navigationItem (activePage : Field Γ String) (page : Page) : View Γ :=
  View.node .button [.text page.label]
    (attrs := [.buttonType .button])
    (events := [{ kind := .click, eventName := page.eventName }])
    (selects := [
      .classSelect activePage page.slug navigationActiveClasses navigationIdleClasses,
      .pressedSelect activePage page.slug
    ])
where
  navigationActiveClasses : String :=
    "min-h-11 w-full rounded-lg bg-accent px-3 py-2 text-left text-sm font-medium " ++
    "text-accent-foreground shadow-sm focus-visible:outline-2 focus-visible:outline-offset-2"
  navigationIdleClasses : String :=
    "min-h-11 w-full rounded-lg px-3 py-2 text-left text-sm font-medium " ++
    "text-muted-foreground focus-visible:outline-2 focus-visible:outline-offset-2"

/--
An accessible, direct-DOM documentation shell. Navigation, all copy, and the
code example are ordinary LeanRx nodes and sinks; CSS generation remains a
build-time concern.
-/
def shell (activePage : Field Γ String) (pages : List Page)
    (eyebrow : RxExpr Γ eyebrowDeps String) (title : RxExpr Γ titleDeps String)
    (lead : RxExpr Γ leadDeps String) (body : RxExpr Γ bodyDeps String)
    (sample : RxExpr Γ sampleDeps String) (note : RxExpr Γ noteDeps String) : View Γ :=
  View.node .div [
    View.node .header [
      View.node .div [
        View.node .span [.text "LR"]
          (attrs := [
            .className
              ("inline-flex size-9 items-center justify-center rounded-lg bg-primary text-sm " ++
               "font-bold text-primary-foreground")
          ]),
        View.node .div [
          View.node .strong [.text "LeanRx"]
            (attrs := [.className "block text-sm font-semibold text-foreground"]),
          View.node .span [.text "Documentation framework dogfood"]
            (attrs := [.className "block text-xs text-muted-foreground"])
        ]
      ] (attrs := [.className "flex items-center gap-3"]),
      View.node .span [.text "Unreleased experiment"]
        (attrs := [
          .className
            ("rounded-full border border-border bg-muted px-3 py-1 text-xs font-medium " ++
             "text-muted-foreground")
        ])
    ] (attrs := [
      .className
        "mx-auto flex min-h-16 max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8"
    ]),
    View.node .div [
      View.node .aside [
        View.node .nav (pages.map (navigationItem activePage))
          (attrs := [
            .className "grid grid-cols-2 gap-1 sm:grid-cols-3 lg:grid-cols-1",
            .ariaLabel "Documentation"
          ])
      ] (attrs := [.className "border-b border-border p-4 sm:p-6 lg:border-b-0 lg:border-r"]),
      View.node .main [
        View.node .article [
          View.node .p [.scalarText "pageEyebrow" eyebrow]
            (attrs := [
              .className "mb-3 text-sm font-semibold uppercase tracking-[0.16em] text-primary"
            ]),
          View.node .h1 [.scalarText "pageTitle" title]
            (attrs := [
              .className
                ("max-w-3xl text-balance text-3xl font-bold tracking-tight text-foreground " ++
                 "sm:text-4xl")
            ]),
          View.node .p [.scalarText "pageLead" lead]
            (attrs := [
              .className "mt-5 max-w-3xl text-pretty text-lg leading-8 text-muted-foreground"
            ]),
          View.node .section [
            View.node .h2 [.text "What to know"]
              (attrs := [.className "text-xl font-semibold tracking-tight text-foreground"]),
            View.node .p [.scalarText "pageBody" body]
              (attrs := [
                .className "mt-3 whitespace-pre-line text-base leading-8 text-muted-foreground"
              ])
          ] (attrs := [.className "mt-10"]),
          View.node .section [
            View.node .h2 [.text "Try it"]
              (attrs := [.className "text-xl font-semibold tracking-tight text-foreground"]),
            View.node .div [UI.codeBlock "pageSample" sample]
              (attrs := [.className "mt-4"])
          ] (attrs := [.className "mt-10"]),
          View.node .div [
            UI.callout "Reality check"
              (View.node .p [.scalarText "pageNote" note]
                (attrs := [.className "mt-1 whitespace-pre-line"]))
          ] (attrs := [.className "mt-8"])
        ] (attrs := [.className "mx-auto max-w-4xl px-5 py-10 sm:px-8 sm:py-14"])
      ] (attrs := [.className "min-w-0"])
    ] (attrs := [
      .className
        "mx-auto grid max-w-7xl border-t border-border lg:grid-cols-[16rem_minmax(0,1fr)]"
    ]),
    View.node .footer [
      View.node .p [
        .text "Built by the same checked component, direct-DOM backend, and atomic publisher it documents."
      ]
    ] (attrs := [
      .className
        ("border-t border-border px-5 py-8 text-center text-sm text-muted-foreground " ++
         "pb-[max(2rem,env(safe-area-inset-bottom))]")
    ])
  ] (attrs := [.className "min-h-screen bg-background text-foreground"])

end LeanRx.Docs
