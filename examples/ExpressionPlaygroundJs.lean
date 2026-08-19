import LeanRx
import examples.ExpressionPlayground

namespace LeanRxExamples.ExpressionPlaygroundJs

open LeanRx
open LeanRxExamples.ExpressionPlayground

private def emit (directory : System.FilePath) (filename exportName : String)
    (expr : RxExpr Pricing deps α) : IO Unit := do
  let ir := Lower.rxExpr expr
  let emitted ← match Backend.Scalar.moduleFor exportName
      #[{ name := "price", valueType := .int },
        { name := "quantity", valueType := .int },
        { name := "threshold", valueType := .int }] ir with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"playground lowering failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"playground printing failed: {error.code}"
  IO.FS.writeFile (directory / filename) source
  IO.FS.writeFile (directory / (filename ++ ".manifest.json")) <|
    (Backend.ArtifactManifest.scalar filename emitted).json

private def resultJson (name : String) (values : Store Pricing) : String :=
  "{\"name\":" ++ Js.Printer.stringLiteral name ++
    ",\"subtotal\":" ++ Js.Printer.stringLiteral (toString (subtotal.eval values)) ++
    ",\"isLarge\":" ++ (if isLarge.eval values then "true" else "false") ++
    ",\"label\":" ++ Js.Printer.stringLiteral (label.eval values) ++ "}"

def generate (directory : System.FilePath) : IO Unit := do
  IO.FS.createDirAll directory
  emit directory "subtotal.mjs" "subtotal" subtotal
  emit directory "is_large.mjs" "isLarge" isLarge
  emit directory "label.mjs" "label" label
  let expected := "[" ++
    resultJson "first" (store 12 4 40) ++ "," ++
    resultJson "second" (store 5 4 40) ++ "]\n"
  IO.FS.writeFile (directory / "expected.json") expected

end LeanRxExamples.ExpressionPlaygroundJs

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.ExpressionPlaygroundJs.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Expression Playground JavaScript output directory"
