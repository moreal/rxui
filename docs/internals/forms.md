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
are private. Compile-fail fixtures check that `RawForm` cannot be passed to submission
and the command cannot be forged directly.

Temperature parsing currently accepts signed ASCII integer text. Digit separators
such as `1_000` and `-0_1`, leading `+`, whitespace, decimals, and locale-specific
digits are rejected before Lean's standard numeric parser is called; this closed
grammar is exactly the browser regex grammar. Conversion uses
truncating integer division (`Int.tdiv`); the specialized BigInt browser lowering
matches native Lean for negative values in native-derived Chromium cases. Invalid raw text remains an explicit
`LRX-TYPE-201` error. Decimal/locale-aware temperature input is a future parser,
not silently accepted by the integer contract.

These are type and native-semantic guarantees. The generated JavaScript validator,
DOM property writes, and browser remain in the TCB; native expected artifacts,
deterministic code checks, and Chromium tests provide executable evidence rather
than a backend proof.

The closed `DomProperty` capability currently permits only typed `value : String`,
`checked : Bool`, and `disabled : Bool` writes. `ControlEvent` similarly fixes
the payload extraction for text input/change, checked change, submit, keydown,
focus, and blur. `StateControlBinding` privately joins a typed source update to
its only valid payload adapter and reflected property. The shared form backend
lowering pattern-matches these constructors to choose the host listener and
property name; production form emitters do not accept arbitrary equivalents.
The DOM host exposes one small listener adapter per payload kind and a property
setter; it still performs no parsing, validation, dependency discovery, or
scheduling.

Generated integer parsing uses compiler-owned regex literals and calls `BigInt`
only after a lexical match, so invalid text cannot throw. Native parsing applies
the same lexical guard before `String.toInt?`/`String.toNat?`, preventing Lean-only
digit-separator acceptance. A checked Temperature update plan records the edited
source, active-edited-scale source, and conditional opposite-source write
separately. Parsing/conversion
is event-local update evaluation, followed by one graph propagation phase; it is
not a pair of mutually dependent derived nodes. The checked graph contains both
controlled property sinks, the shared error sink, and both invalid-state sinks.
Each invalid-state sink parses its own raw source; the shared message selects the
active invalid field, with a deterministic Celsius-first fallback. Presentation
is therefore a function of the complete checked store, not hidden event history.
Temperature handlers do not rewrite the control currently being edited,
preserving its exact raw text and cursor, and use source equality plus guarded
property/error/invalid caches. Validated Form uses the same
closed natural/ASCII-trim rules as native Lean, maintains `value`, `checked`,
`disabled`, and `aria-invalid`, prevents native form navigation, and revalidates
inside submit. Submit-authoritative name and age state synchronize on `input`;
the separate text `change` capability is an observational payload trace and
cannot leave visible values ahead of validated state. Only a valid result
produces the fake command trace/status.

The component manifest's `textSinkCount` counts text-node destinations, not DOM
properties or attributes. Temperature has one text sink (the parse error);
Validated Form has three validation-error text sinks plus submission status.
Property and attribute sinks remain explicit graph nodes/features without being
misreported as text nodes.

The host only extracts event payloads, prevents submit default behavior, sets a
typed property chosen by the backend, and allocates document-unique accessibility
IDs. It does not parse, validate, schedule, or execute commands.
