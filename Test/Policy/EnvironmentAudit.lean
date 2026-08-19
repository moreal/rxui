import Lean

open Lean Elab Command

/-- Audit the complete imported `LeanRx.*` environment. The reviewed unsafe
allowlist is intentionally empty; adding an entry requires trust-boundary review. -/
elab "#leanrx_environment_audit" : command => do
  let env ← getEnv
  let reviewedUnsafe : Array Name := #[
    `LeanRx.Field.index._unsafe_rec,
    `LeanRx.Field.name._unsafe_rec,
    `LeanRx.Field.toFin._unsafe_rec,
    `LeanRx.Schema.names._unsafe_rec,
    `LeanRx.Schema.size._unsafe_rec,
    `LeanRx.Store.get._unsafe_rec,
    `LeanRx.Store.set._unsafe_rec,
    `LeanRx.instBEqJsType.beq._unsafe_rec,
    `LeanRx.instDecidableEqJsType.decEq._unsafe_rec,
    `LeanRx.instReprJsType.repr._unsafe_rec
  ]
  -- Generated injectivity plus named membership/agreement lemmas use Lean's
  -- standard proposition-extensionality axiom. Each exact pair is reviewed;
  -- every other theorem/axiom pair fails closed.
  let reviewedAxiomUses : Array (Name × Array Name) := #[
    (`LeanRx.DepSet.contains_singleton, #[``propext]),
    (`LeanRx.DepSet.contains_singleton._simp_1_2, #[``propext]),
    (`LeanRx.DepSet.contains_union_left, #[``propext]),
    (`LeanRx.DepSet.contains_union_right, #[``propext]),
    (`LeanRx.DepSet.hasId_empty, #[``propext]),
    (`LeanRx.DepSet.hasId_singleton, #[``propext]),
    (`LeanRx.DepSet.hasId_union, #[``propext]),
    (`LeanRx.DepSet.hasId_union._simp_1_3, #[``propext]),
    (`LeanRx.DepSet.mk.injEq, #[``propext]),
    (`LeanRx.SourcePos.mk.injEq, #[``propext]),
    (`LeanRx.SourceSpan.mk.injEq, #[``propext]),
    (`LeanRx.Field.there.injEq, #[``propext]),
    (`LeanRx.JsType.array.injEq, #[``propext]),
    (`LeanRx.JsType.object.injEq, #[``propext]),
    (`LeanRx.Schema.field.injEq, #[``propext]),
    (`LeanRx.Store.agreeOn_empty, #[``propext]),
    (`LeanRx.Store.agreeOn_union_left, #[``propext]),
    (`LeanRx.Store.agreeOn_union_right, #[``propext]),
    (`LeanRx.Store.cons.injEq, #[``propext])
  ]
  let declarations := (env.constants.toList.filter fun (name, _) =>
      name.toString.startsWith "LeanRx.").toArray.qsort fun a b =>
    Name.lt a.1 b.1
  let requiredImports : Array Name := #[`LeanRx.version, `LeanRx.SourcePos]
  for name in requiredImports do
    unless declarations.any (fun entry => entry.1 == name) do
      throwError "environment audit is missing required imported declaration '{name}'"
  let mut theoremCount : Nat := 0
  for (name, info) in declarations do
    if info.isAxiom then
      throwError "public LeanRx axiom '{name}' is not allowed"
    if info.isUnsafe || info.isPartial then
      unless reviewedUnsafe.contains name do
        throwError "unreviewed unsafe or partial LeanRx declaration: '{name}'"
      logInfo m!"reviewed generated unsafe recursion helper: {name}"
    if info.isTheorem then
      theoremCount := theoremCount + 1
      let axioms ← Lean.collectAxioms name
      let expected := reviewedAxiomUses.find? (fun entry => entry.1 == name)
        |>.map (·.2) |>.getD #[]
      unless axioms == expected do
        throwError "public theorem '{name}' axiom manifest mismatch; expected {expected.toList}, got {axioms.toList}"
      unless axioms.isEmpty do
        logInfo m!"reviewed axiom use: {name} -> {axioms.toList}"
  for (name, _) in reviewedAxiomUses do
    unless declarations.any (fun entry => entry.1 == name) do
      throwError "reviewed axiom manifest names missing declaration '{name}'"
  for name in reviewedUnsafe do
    unless declarations.any (fun entry => entry.1 == name) do
      throwError "reviewed unsafe manifest names missing declaration '{name}'"
  logInfo m!"LeanRx environment audit passed for {theoremCount} public theorem(s)"
