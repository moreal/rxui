import Lean
import LeanRx

open Lean Elab Command

/-- Audit every theorem in the public `LeanRx` namespace, so adding a theorem
cannot silently omit it from a hand-maintained manifest. -/
elab "#leanrx_axiom_audit" : command => do
  let env ← getEnv
  let declarations := (env.constants.map₂.toList.filter fun (name, _) =>
      name.toString.startsWith "LeanRx.").toArray.qsort fun a b =>
    Name.lt a.1 b.1
  let mut theoremCount : Nat := 0
  for (name, info) in declarations do
    if info.isAxiom then
      throwError "public LeanRx axiom '{name}' is not allowed"
    if info.isTheorem then
      theoremCount := theoremCount + 1
      let axioms ← Lean.collectAxioms name
      unless axioms.isEmpty do
        throwError "public theorem '{name}' depends on unreviewed axioms: {axioms.toList}"
  logInfo m!"LeanRx axiom audit passed for {theoremCount} public theorem(s)"

#leanrx_axiom_audit
