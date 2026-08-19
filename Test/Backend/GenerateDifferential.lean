import LeanRx.Backend.Scalar
import LeanRx.Backend.Manifest
import LeanRx.Backend.JsPrinter
import LeanRx.Core.Expr
import LeanRx.Lower.RxExpr

namespace LeanRxTest.Backend.GenerateDifferential

open LeanRx

inductive RuntimeValue where
  | bool (value : Bool)
  | string (value : String)
  | bigint (value : Int)

namespace RuntimeValue

def json : RuntimeValue → String
  | .bool value =>
      "{\"type\":\"bool\",\"value\":" ++ (if value then "true" else "false") ++ "}"
  | .string value =>
      "{\"type\":\"string\",\"value\":" ++ Js.Printer.stringLiteral value ++ "}"
  | .bigint value =>
      "{\"type\":\"bigint\",\"value\":" ++
        Js.Printer.stringLiteral (toString value) ++ "}"

end RuntimeValue

structure Case where
  moduleName : String
  exportName : String := "evaluate"
  args : List RuntimeValue
  expected : RuntimeValue

namespace Case

def json (value : Case) : String :=
  "{\"module\":" ++ Js.Printer.stringLiteral value.moduleName ++
    ",\"export\":" ++ Js.Printer.stringLiteral value.exportName ++ ",\"args\":[" ++
    String.intercalate "," (value.args.map RuntimeValue.json) ++
    "],\"expected\":" ++ value.expected.json ++ "}"

end Case

private def input (name : String) (valueType : RuntimeTypeId) : Backend.Scalar.InputSpec :=
  { name, valueType }

private abbrev UnarySchema (α : Type) : Schema := .field "value" α .empty

private def unaryExpr [RuntimeRep α] (op : UnaryPrim α β) :=
  RxExpr.unary op (RxExpr.read (.here : Field (UnarySchema α) α))

private abbrev BinarySchema (α β : Type) : Schema :=
  .field "left" α <| .field "right" β .empty

private def binaryExpr [RuntimeRep α] [RuntimeRep β] (op : BinaryPrim α β γ) :=
  RxExpr.binary op
    (RxExpr.read (.here : Field (BinarySchema α β) α))
    (RxExpr.read (.there .here : Field (BinarySchema α β) β))

private abbrev ChoiceSchema : Schema :=
  .field "condition" Bool <| .field "yes" String <| .field "no" String .empty

private def conditionalExpr := RxExpr.ifThenElse
  (RxExpr.read (.here : Field ChoiceSchema Bool))
  (RxExpr.read (.there .here : Field ChoiceSchema String))
  (RxExpr.read (.there (.there .here) : Field ChoiceSchema String))

private def literalBool : RxExpr .empty (DepSet.empty .empty) Bool := .literal (.bool true)
private def literalString : RxExpr .empty (DepSet.empty .empty) String :=
  .literal (.string "린\nRx\x00")
private def literalInt : RxExpr .empty (DepSet.empty .empty) Int :=
  .literal (.int (-9007199254740993))
private def literalNat : RxExpr .empty (DepSet.empty .empty) Nat :=
  .literal (.nat 9007199254740993)

private def writeModuleAs (directory : System.FilePath) (filename requestedExport : String)
    (inputs : Array Backend.Scalar.InputSpec) (value : RxExpr Γ deps α) : IO Unit := do
  let emitted ← match Backend.Scalar.moduleFor requestedExport inputs (Lower.rxExpr value) with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"differential emission failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"differential printing failed: {error.code}"
  let compact ← match Js.Printer.module .compact emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"compact differential printing failed: {error.code}"
  IO.FS.writeFile (directory / filename) source
  let compactFilename := (filename.dropEnd 4).toString ++ ".compact.mjs"
  IO.FS.writeFile (directory / compactFilename) compact
  IO.FS.writeFile (directory / (filename ++ ".manifest.json")) <|
    (Backend.ArtifactManifest.scalar filename emitted).json
  IO.FS.writeFile (directory / (compactFilename ++ ".manifest.json")) <|
    (Backend.ArtifactManifest.scalar compactFilename emitted).json

private def writeModule (directory : System.FilePath) (filename : String)
    (inputs : Array Backend.Scalar.InputSpec) (value : RxExpr Γ deps α) : IO Unit :=
  writeModuleAs directory filename "evaluate" inputs value

private def emitModules (directory : System.FilePath) : IO Unit := do
  writeModule directory "literal_bool.mjs" #[] literalBool
  writeModule directory "literal_string.mjs" #[] literalString
  writeModule directory "literal_int.mjs" #[] literalInt
  writeModule directory "literal_nat.mjs" #[] literalNat
  writeModule directory "bool_not.mjs" #[input "value" .bool] <| unaryExpr .boolNot
  writeModule directory "int_neg.mjs" #[input "value" .int] <| unaryExpr .intNeg
  writeModule directory "nat_to_int.mjs" #[input "value" .nat] <| unaryExpr .natToInt
  writeModule directory "int_to_string.mjs" #[input "value" .int] <| unaryExpr .intToString
  writeModule directory "nat_to_string.mjs" #[input "value" .nat] <| unaryExpr .natToString
  writeModule directory "int_add.mjs" #[input "left" .int, input "right" .int] <|
    binaryExpr .intAdd
  writeModule directory "int_sub.mjs" #[input "left" .int, input "right" .int] <|
    binaryExpr .intSub
  writeModule directory "int_mul.mjs" #[input "left" .int, input "right" .int] <|
    binaryExpr .intMul
  writeModule directory "int_mod.mjs" #[input "left" .int, input "right" .int] <|
    binaryExpr .intMod
  writeModule directory "int_eq.mjs" #[input "left" .int, input "right" .int] <|
    binaryExpr .intEq
  writeModule directory "int_lt.mjs" #[input "left" .int, input "right" .int] <|
    binaryExpr .intLt
  writeModule directory "int_le.mjs" #[input "left" .int, input "right" .int] <|
    binaryExpr .intLe
  writeModule directory "nat_add.mjs" #[input "left" .nat, input "right" .nat] <|
    binaryExpr .natAdd
  writeModule directory "nat_sub.mjs" #[input "left" .nat, input "right" .nat] <|
    binaryExpr .natSub
  writeModule directory "nat_mul.mjs" #[input "left" .nat, input "right" .nat] <|
    binaryExpr .natMul
  writeModule directory "nat_mod.mjs" #[input "left" .nat, input "right" .nat] <|
    binaryExpr .natMod
  writeModule directory "nat_eq.mjs" #[input "left" .nat, input "right" .nat] <|
    binaryExpr .natEq
  writeModule directory "nat_lt.mjs" #[input "left" .nat, input "right" .nat] <|
    binaryExpr .natLt
  writeModule directory "nat_le.mjs" #[input "left" .nat, input "right" .nat] <|
    binaryExpr .natLe
  writeModule directory "bool_and.mjs" #[input "left" .bool, input "right" .bool] <|
    binaryExpr .boolAnd
  writeModule directory "bool_or.mjs" #[input "left" .bool, input "right" .bool] <|
    binaryExpr .boolOr
  writeModule directory "string_append.mjs"
      #[input "left" .string, input "right" .string] <| binaryExpr .stringAppend
  writeModule directory "string_eq.mjs"
      #[input "left" .string, input "right" .string] <| binaryExpr .stringEq
  writeModule directory "conditional.mjs"
      #[input "condition" .bool, input "yes" .string, input "no" .string] conditionalExpr
  writeModuleAs directory "hostile_names.mjs" "enum" #[input "eval" .int] <|
    unaryExpr .intNeg

private def intBinary (moduleName : String) (left right expected : Int) : Case :=
  { moduleName, args := [.bigint left, .bigint right], expected := .bigint expected }

private def natBinary (moduleName : String) (left right expected : Nat) : Case :=
  { moduleName
    args := [.bigint (Int.ofNat left), .bigint (Int.ofNat right)]
    expected := .bigint (Int.ofNat expected) }

private def cases : List Case := [
  { moduleName := "literal_bool.mjs", args := [], expected := .bool true },
  { moduleName := "literal_string.mjs", args := [], expected := .string "린\nRx\x00" },
  { moduleName := "literal_int.mjs", args := [], expected := .bigint (-9007199254740993) },
  { moduleName := "literal_nat.mjs", args := [], expected := .bigint 9007199254740993 },
  { moduleName := "hostile_names.mjs", exportName := "enum_", args := [.bigint 7],
    expected := .bigint (-7) },
  { moduleName := "bool_not.mjs", args := [.bool true],
    expected := .bool (UnaryPrim.boolNot.eval true) },
  { moduleName := "int_neg.mjs", args := [.bigint 7],
    expected := .bigint (UnaryPrim.intNeg.eval 7) },
  { moduleName := "nat_to_int.mjs", args := [.bigint 9007199254740993],
    expected := .bigint (UnaryPrim.natToInt.eval 9007199254740993) },
  { moduleName := "int_to_string.mjs", args := [.bigint (-9007199254740993)],
    expected := .string (UnaryPrim.intToString.eval (-9007199254740993)) },
  { moduleName := "nat_to_string.mjs", args := [.bigint 9007199254740993],
    expected := .string (UnaryPrim.natToString.eval 9007199254740993) },
  intBinary "int_add.mjs" 9007199254740993 9 (BinaryPrim.intAdd.eval 9007199254740993 9),
  intBinary "int_sub.mjs" (-7) 5 (BinaryPrim.intSub.eval (-7) 5),
  intBinary "int_mul.mjs" (-7) 5 (BinaryPrim.intMul.eval (-7) 5),
  intBinary "int_mod.mjs" (-7) 5 (BinaryPrim.intMod.eval (-7) 5),
  intBinary "int_mod.mjs" 7 0 (BinaryPrim.intMod.eval 7 0),
  intBinary "int_mod.mjs" 7 (-5) (BinaryPrim.intMod.eval 7 (-5)),
  intBinary "int_mod.mjs" (-7) (-5) (BinaryPrim.intMod.eval (-7) (-5)),
  { moduleName := "int_eq.mjs", args := [.bigint (-7), .bigint (-7)],
    expected := .bool (BinaryPrim.intEq.eval (-7) (-7)) },
  { moduleName := "int_eq.mjs", args := [.bigint (-7), .bigint 5],
    expected := .bool (BinaryPrim.intEq.eval (-7) 5) },
  { moduleName := "int_lt.mjs", args := [.bigint (-7), .bigint 5],
    expected := .bool (BinaryPrim.intLt.eval (-7) 5) },
  { moduleName := "int_lt.mjs", args := [.bigint 5, .bigint 5],
    expected := .bool (BinaryPrim.intLt.eval 5 5) },
  { moduleName := "int_lt.mjs", args := [.bigint 7, .bigint 5],
    expected := .bool (BinaryPrim.intLt.eval 7 5) },
  { moduleName := "int_le.mjs", args := [.bigint (-7), .bigint 5],
    expected := .bool (BinaryPrim.intLe.eval (-7) 5) },
  { moduleName := "int_le.mjs", args := [.bigint 5, .bigint 5],
    expected := .bool (BinaryPrim.intLe.eval 5 5) },
  { moduleName := "int_le.mjs", args := [.bigint 7, .bigint 5],
    expected := .bool (BinaryPrim.intLe.eval 7 5) },
  natBinary "nat_add.mjs" 9007199254740993 9 (BinaryPrim.natAdd.eval 9007199254740993 9),
  natBinary "nat_sub.mjs" 5 7 (BinaryPrim.natSub.eval 5 7),
  natBinary "nat_sub.mjs" 7 5 (BinaryPrim.natSub.eval 7 5),
  natBinary "nat_mul.mjs" 7 5 (BinaryPrim.natMul.eval 7 5),
  natBinary "nat_mod.mjs" 7 5 (BinaryPrim.natMod.eval 7 5),
  natBinary "nat_mod.mjs" 7 0 (BinaryPrim.natMod.eval 7 0),
  { moduleName := "nat_eq.mjs", args := [.bigint 7, .bigint 5],
    expected := .bool (BinaryPrim.natEq.eval 7 5) },
  { moduleName := "nat_eq.mjs", args := [.bigint 5, .bigint 5],
    expected := .bool (BinaryPrim.natEq.eval 5 5) },
  { moduleName := "nat_lt.mjs", args := [.bigint 5, .bigint 7],
    expected := .bool (BinaryPrim.natLt.eval 5 7) },
  { moduleName := "nat_lt.mjs", args := [.bigint 7, .bigint 7],
    expected := .bool (BinaryPrim.natLt.eval 7 7) },
  { moduleName := "nat_lt.mjs", args := [.bigint 9, .bigint 7],
    expected := .bool (BinaryPrim.natLt.eval 9 7) },
  { moduleName := "nat_le.mjs", args := [.bigint 5, .bigint 7],
    expected := .bool (BinaryPrim.natLe.eval 5 7) },
  { moduleName := "nat_le.mjs", args := [.bigint 7, .bigint 7],
    expected := .bool (BinaryPrim.natLe.eval 7 7) },
  { moduleName := "nat_le.mjs", args := [.bigint 9, .bigint 7],
    expected := .bool (BinaryPrim.natLe.eval 9 7) },
  { moduleName := "bool_and.mjs", args := [.bool true, .bool false],
    expected := .bool (BinaryPrim.boolAnd.eval true false) },
  { moduleName := "bool_or.mjs", args := [.bool true, .bool false],
    expected := .bool (BinaryPrim.boolOr.eval true false) },
  { moduleName := "string_append.mjs", args := [.string "린\n", .string "Rx\x00"],
    expected := .string (BinaryPrim.stringAppend.eval "린\n" "Rx\x00") },
  { moduleName := "string_eq.mjs", args := [.string "한글", .string "한글"],
    expected := .bool (BinaryPrim.stringEq.eval "한글" "한글") },
  { moduleName := "string_eq.mjs", args := [.string "한글", .string "다름"],
    expected := .bool (BinaryPrim.stringEq.eval "한글" "다름") },
  { moduleName := "conditional.mjs", args := [.bool true, .string "yes", .string "no"],
    expected := .string "yes" },
  { moduleName := "conditional.mjs", args := [.bool false, .string "yes", .string "no"],
    expected := .string "no" }
]

def generate (directory : System.FilePath) : IO Unit := do
  IO.FS.createDirAll directory
  emitModules directory
  let manifest := "[\n" ++ String.intercalate ",\n" (cases.map Case.json) ++ "\n]\n"
  IO.FS.writeFile (directory / "cases.json") manifest

end LeanRxTest.Backend.GenerateDifferential

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ =>
      LeanRxTest.Backend.GenerateDifferential.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected generated-JavaScript output directory"
