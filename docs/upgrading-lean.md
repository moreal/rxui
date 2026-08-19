# Upgrading Lean

LeanRx starts on `leanprover/lean4:v4.33.0`. Toolchain changes are isolated from
feature commits and require all of the following:

1. read the official release notes from the current version through the target;
2. update this document with affected APIs and migrations;
3. build every Lean module and executable;
4. run placeholder, axiom, and proof checks;
5. run native, property, differential, determinism, and browser gates;
6. review generated graph and JavaScript fixtures byte-for-byte;
7. inspect every project import of internal metaprogramming/compiler APIs;
8. record benchmark changes;
9. commit the toolchain upgrade separately.

The exact toolchain is also embedded in `LeanRx/Core/Version.lean` for generated
artifact manifests. Update it in the same isolated upgrade commit and regenerate
the manifest goldens.

## Internal API inventory

- `Test/Policy/EnvironmentAudit.lean` imports `Lean` for a test-only environment
  audit. It uses `Environment.constants`, `SMap.toList`,
  `ConstantInfo.isAxiom`/`isUnsafe`/`isPartial`/`isTheorem`, and
  `Lean.collectAxioms`. Recheck these names and imported/local environment
  behavior on every toolchain upgrade.
- Production code uses no internal Lean metaprogramming or compiler API.
- `LeanRx/Elab/Component.lean` uses public command/term elaboration APIs and
  `Lean.Meta.evalExpr` to execute the generated component checker at compile
  time. The one compiler-generated unsafe wrapper is exact-name audited; recheck
  its name and evaluation behavior on every Lean upgrade.
- `lakefile.lean` uses public Lake declarations.
