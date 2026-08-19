# Form parsing and validation contract

M7 parsers and validators are pure, total Lean values. A `Parser α` returns
`Except ValidationError α`; it never throws and never silently substitutes a
default. Validators refine parsed values through private constructors.

The first public refinements are:

- `NonEmptyString`, which stores a trimmed nonempty name;
- `BoundedNat minimum maximum`, which stores a natural and both bound proofs;
- `AcceptedTerms`, which can only be constructed from `true`;
- `ValidatedForm`, which packages a nonempty name, age in `[18, 120]`, and
  accepted-terms capability.

`validateForm` accumulates independent name, age, and acceptance errors. Only its `.valid`
branch exposes `ValidatedForm`, and only that value can enter `Form.submit` to
produce the fake command payload. Both the validated value and command constructors
are private. Compile-fail fixtures prove `RawForm` cannot be passed to submission
and the command cannot be forged directly.

Temperature parsing currently accepts signed ASCII integer text. Digit separators
such as `1_000` and `-0_1`, leading `+`, whitespace, decimals, and locale-specific
digits are rejected before Lean's standard numeric parser is called; this closed
grammar is exactly the browser regex grammar. Conversion uses
truncating integer division (`Int.tdiv`) so the future BigInt browser lowering can
match native Lean for negative values. Invalid raw text remains an explicit
`LRX-TYPE-201` error. Decimal/locale-aware temperature input is a future parser,
not silently accepted by the integer contract.

These are type and native-semantic guarantees. The generated JavaScript validator,
DOM property writes, and browser remain in the TCB; native expected artifacts,
deterministic code checks, and Chromium tests provide executable evidence rather
than a backend proof.

The closed `DomProperty` capability currently permits only typed `value : String`,
`checked : Bool`, and `disabled : Bool` writes. `ControlEvent` similarly fixes
the payload extraction for text input/change, checked change, submit, keydown,
focus, and blur. The DOM host exposes one small listener adapter per payload kind
and a property setter; it still performs no parsing, validation, dependency
discovery, or scheduling. Backends must select these primitives from the typed
constructors rather than accepting arbitrary property/event strings.

Generated integer parsing uses compiler-owned regex literals and calls `BigInt`
only after a lexical match, so invalid text cannot throw. Native parsing applies
the same lexical guard before `String.toInt?`/`String.toNat?`, preventing Lean-only
digit-separator acceptance. Temperature handlers do
not rewrite the control currently being edited, preserving its cursor, and use
source equality plus guarded property/error caches. Validated Form uses the same
closed natural/ASCII-trim rules as native Lean, maintains `value`, `checked`,
`disabled`, and `aria-invalid`, prevents native form navigation, and revalidates
inside submit. Only a valid result produces the fake command trace/status.

The host only extracts event payloads, prevents submit default behavior, sets a
typed property chosen by the backend, and allocates document-unique accessibility
IDs. It does not parse, validate, schedule, or execute commands.
