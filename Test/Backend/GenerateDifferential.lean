import LeanRx.Backend.Scalar
import LeanRx.Backend.JsPrinter
import LeanRx.Core.Expr

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
  args : List RuntimeValue
  expected : RuntimeValue

namespace Case

def json (value : Case) : String :=
  "{\"module\":" ++ Js.Printer.stringLiteral value.moduleName ++
    ",\"export\":\"evaluate\",\"args\":[" ++
    String.intercalate "," (value.args.map RuntimeValue.json) ++
    "],\"expected\":" ++ value.expected.json ++ "}"

end Case

private def boolInput (index : Nat) (name : String) : ReactiveIR.Expr Bool :=
  .input .bool index name

private def stringInput (index : Nat) (name : String) : ReactiveIR.Expr String :=
  .input .string index name

private def intInput (index : Nat) (name : String) : ReactiveIR.Expr Int :=
  .input .int index name

private def natInput (index : Nat) (name : String) : ReactiveIR.Expr Nat :=
  .input .nat index name

private def writeModule (directory : System.FilePath) (filename : String)
    (inputs : Array String) (value : ReactiveIR.Expr α) : IO Unit := do
  let emitted ← match Backend.Scalar.moduleFor "evaluate" inputs value with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"differential emission failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"differential printing failed: {error.code}"
  IO.FS.writeFile (directory / filename) source

private def emitModules (directory : System.FilePath) : IO Unit := do
  writeModule directory "bool_not.mjs" #["value"] <|
    .unary .boolNot (boolInput 0 "value")
  writeModule directory "int_neg.mjs" #["value"] <|
    .unary .intNeg (intInput 0 "value")
  writeModule directory "nat_to_int.mjs" #["value"] <|
    .unary .natToInt (natInput 0 "value")
  writeModule directory "int_to_string.mjs" #["value"] <|
    .unary .intToString (intInput 0 "value")
  writeModule directory "nat_to_string.mjs" #["value"] <|
    .unary .natToString (natInput 0 "value")
  writeModule directory "int_add.mjs" #["left", "right"] <|
    .binary .intAdd (intInput 0 "left") (intInput 1 "right")
  writeModule directory "int_sub.mjs" #["left", "right"] <|
    .binary .intSub (intInput 0 "left") (intInput 1 "right")
  writeModule directory "int_mul.mjs" #["left", "right"] <|
    .binary .intMul (intInput 0 "left") (intInput 1 "right")
  writeModule directory "int_mod.mjs" #["left", "right"] <|
    .binary .intMod (intInput 0 "left") (intInput 1 "right")
  writeModule directory "int_eq.mjs" #["left", "right"] <|
    .binary .intEq (intInput 0 "left") (intInput 1 "right")
  writeModule directory "int_lt.mjs" #["left", "right"] <|
    .binary .intLt (intInput 0 "left") (intInput 1 "right")
  writeModule directory "int_le.mjs" #["left", "right"] <|
    .binary .intLe (intInput 0 "left") (intInput 1 "right")
  writeModule directory "nat_add.mjs" #["left", "right"] <|
    .binary .natAdd (natInput 0 "left") (natInput 1 "right")
  writeModule directory "nat_sub.mjs" #["left", "right"] <|
    .binary .natSub (natInput 0 "left") (natInput 1 "right")
  writeModule directory "nat_mul.mjs" #["left", "right"] <|
    .binary .natMul (natInput 0 "left") (natInput 1 "right")
  writeModule directory "nat_mod.mjs" #["left", "right"] <|
    .binary .natMod (natInput 0 "left") (natInput 1 "right")
  writeModule directory "nat_eq.mjs" #["left", "right"] <|
    .binary .natEq (natInput 0 "left") (natInput 1 "right")
  writeModule directory "nat_lt.mjs" #["left", "right"] <|
    .binary .natLt (natInput 0 "left") (natInput 1 "right")
  writeModule directory "nat_le.mjs" #["left", "right"] <|
    .binary .natLe (natInput 0 "left") (natInput 1 "right")
  writeModule directory "bool_and.mjs" #["left", "right"] <|
    .binary .boolAnd (boolInput 0 "left") (boolInput 1 "right")
  writeModule directory "bool_or.mjs" #["left", "right"] <|
    .binary .boolOr (boolInput 0 "left") (boolInput 1 "right")
  writeModule directory "string_append.mjs" #["left", "right"] <|
    .binary .stringAppend (stringInput 0 "left") (stringInput 1 "right")
  writeModule directory "string_eq.mjs" #["left", "right"] <|
    .binary .stringEq (stringInput 0 "left") (stringInput 1 "right")
  writeModule directory "conditional.mjs" #["condition", "yes", "no"] <|
    .conditional (boolInput 0 "condition") (stringInput 1 "yes") (stringInput 2 "no")

private def intBinary (moduleName : String) (left right expected : Int) : Case :=
  { moduleName, args := [.bigint left, .bigint right], expected := .bigint expected }

private def natBinary (moduleName : String) (left right expected : Nat) : Case :=
  { moduleName
    args := [.bigint (Int.ofNat left), .bigint (Int.ofNat right)]
    expected := .bigint (Int.ofNat expected) }

private def cases : List Case := [
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
  { moduleName := "int_lt.mjs", args := [.bigint (-7), .bigint 5],
    expected := .bool (BinaryPrim.intLt.eval (-7) 5) },
  { moduleName := "int_le.mjs", args := [.bigint 5, .bigint 5],
    expected := .bool (BinaryPrim.intLe.eval 5 5) },
  natBinary "nat_add.mjs" 9007199254740993 9 (BinaryPrim.natAdd.eval 9007199254740993 9),
  natBinary "nat_sub.mjs" 5 7 (BinaryPrim.natSub.eval 5 7),
  natBinary "nat_sub.mjs" 7 5 (BinaryPrim.natSub.eval 7 5),
  natBinary "nat_mul.mjs" 7 5 (BinaryPrim.natMul.eval 7 5),
  natBinary "nat_mod.mjs" 7 5 (BinaryPrim.natMod.eval 7 5),
  natBinary "nat_mod.mjs" 7 0 (BinaryPrim.natMod.eval 7 0),
  { moduleName := "nat_eq.mjs", args := [.bigint 7, .bigint 5],
    expected := .bool (BinaryPrim.natEq.eval 7 5) },
  { moduleName := "nat_lt.mjs", args := [.bigint 5, .bigint 7],
    expected := .bool (BinaryPrim.natLt.eval 5 7) },
  { moduleName := "nat_le.mjs", args := [.bigint 7, .bigint 7],
    expected := .bool (BinaryPrim.natLe.eval 7 7) },
  { moduleName := "bool_and.mjs", args := [.bool true, .bool false],
    expected := .bool (BinaryPrim.boolAnd.eval true false) },
  { moduleName := "bool_or.mjs", args := [.bool true, .bool false],
    expected := .bool (BinaryPrim.boolOr.eval true false) },
  { moduleName := "string_append.mjs", args := [.string "린\n", .string "Rx\x00"],
    expected := .string (BinaryPrim.stringAppend.eval "린\n" "Rx\x00") },
  { moduleName := "string_eq.mjs", args := [.string "한글", .string "한글"],
    expected := .bool (BinaryPrim.stringEq.eval "한글" "한글") },
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
