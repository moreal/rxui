# Tailwind and component-library integration

## Tailwind CSS: tested

LeanRx writes static class strings onto safe view nodes. Tailwind v4 can scan
those `.lean` sources exactly as it scans other templates, because every class
is present as a complete token rather than assembled dynamically.

The self-hosted docs use this input:

```css
@import "tailwindcss" source(none);
@source "../LeanRx/UI/Primitives.lean";
@source "../LeanRx/Docs/Framework.lean";
@source "./LeanRxDocs.lean";
```

`examples.LeanRxDocsBuild` runs the pinned `@tailwindcss/cli` inside the atomic
staging directory. The artifact and browser gates verify that responsive,
theme, focus, arbitrary-value, and project component classes exist in the
resulting stylesheet. Tailwind adds no browser runtime.

Prefer CSS variables for semantic colors and change the variables for dark
mode. Do not build class names with arbitrary string concatenation: Tailwind's
scanner needs complete candidates in source.

## shadcn/ui: not directly compatible

The shadcn CLI currently emits React or JavaScript components and configures
React-oriented primitives, import aliases, CSS, and helper dependencies. LeanRx
does not run React components or accept arbitrary JavaScript component escape
hatches, so `shadcn add button` output cannot be imported into a LeanRx view.

Two ideas do transfer cleanly:

1. Tailwind and CSS-variable styling;
2. source ownership instead of an opaque precompiled component package.

`LeanRx.UI` is the first experiment in that direction. Its variants are Lean
inductive values, its controls use native semantics, and the application owns
the code. Matching shadcn's practical breadth would require a Lean-native
registry plus checked accessible primitives for dialogs, menus, popovers,
tooltips, focus management, and keyboard interaction. That work is not present
and is not implied by Tailwind compatibility.

## Current verdict

| Integration | Status | Evidence |
|---|---|---|
| Tailwind v4 CLI | Supported dogfood | Atomic CSS build, artifact assertions, browser layout and axe |
| CSS variables and system dark mode | Supported dogfood | Compiled theme tokens and browser stylesheet |
| `LeanRx.UI` primitives | Experimental | Button, callout, and code-block source plus native/browser tests |
| shadcn/ui React components | Unsupported | Runtime and component-model mismatch |
| shadcn-like Lean registry | Missing | No generator, schema, installer, or compatibility contract |
