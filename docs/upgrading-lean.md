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

## Internal API inventory

None at M0. Public Lake declarations are used in `lakefile.lean`.
