# Form parsing and validation contract

M7 parsers and validators are pure, total Lean values. A `Parser α` returns
`Except ValidationError α`; it never throws and never silently substitutes a
default. Validators refine parsed values through private constructors.

The first public refinements are:

- `NonEmptyString`, which stores a trimmed nonempty name;
- `BoundedNat minimum maximum`, which stores a natural and both bound proofs;
- `ValidatedForm`, which packages a nonempty name and age in `[18, 120]`.

`validateForm` accumulates independent name and age errors. Only its `.valid`
branch exposes `ValidatedForm`, and only that value can enter `Form.submit` to
produce the fake command payload. A compile-fail fixture proves `RawForm` cannot
be passed to submission.

Temperature parsing currently accepts signed ASCII integer text. Conversion uses
truncating integer division (`Int.tdiv`) so the future BigInt browser lowering can
match native Lean for negative values. Invalid raw text remains an explicit
`LRX-TYPE-201` error. Decimal/locale-aware temperature input is a future parser,
not silently accepted by the integer contract.

These are type and native-semantic guarantees. Controlled DOM values, cursor
behavior, generated JavaScript parsing, form prevention, and browser submission
remain M7 implementation/TCB work until their differential and browser gates land.

The closed `DomProperty` capability currently permits only typed `value : String`,
`checked : Bool`, and `disabled : Bool` writes. `ControlEvent` similarly fixes
the payload extraction for text input/change, checked change, submit, keydown,
focus, and blur. The DOM host exposes one small listener adapter per payload kind
and a property setter; it still performs no parsing, validation, dependency
discovery, or scheduling. Backends must select these primitives from the typed
constructors rather than accepting arbitrary property/event strings.
