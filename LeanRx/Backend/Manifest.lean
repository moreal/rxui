import LeanRx.Backend.Scalar
import LeanRx.Backend.JsPrinter
import LeanRx.Core.Version

namespace LeanRx.Backend

structure ComponentManifest where
  compilerVersion : String
  leanToolchain : String
  moduleName : String
  graphHash : String
  runtimeAbi : Nat
  exports : Array String
  stateSlots : Array RuntimeTypeId
  sourceCount : Nat
  derivedCount : Nat
  textSinkCount : Nat
  eventCount : Nat
  hostImports : Array String
  features : Array String
deriving Repr, BEq

namespace ComponentManifest

private def quoted (value : String) : String := Js.Printer.stringLiteral value

private def strings (values : Array String) : String :=
  "[" ++ String.intercalate "," (values.toList.map quoted) ++ "]"

private def types (values : Array RuntimeTypeId) : String :=
  strings (values.map (·.debug))

/-- Stable component ABI metadata. Field order is deliberately fixed. -/
def json (value : ComponentManifest) : String :=
  "{\"compilerVersion\":" ++ quoted value.compilerVersion ++
    ",\"leanToolchain\":" ++ quoted value.leanToolchain ++
    ",\"module\":" ++ quoted value.moduleName ++
    ",\"graphHash\":" ++ quoted value.graphHash ++
    ",\"runtimeAbi\":" ++ toString value.runtimeAbi ++
    ",\"exports\":" ++ strings value.exports ++
    ",\"stateSlots\":" ++ types value.stateSlots ++
    ",\"sourceCount\":" ++ toString value.sourceCount ++
    ",\"derivedCount\":" ++ toString value.derivedCount ++
    ",\"textSinkCount\":" ++ toString value.textSinkCount ++
    ",\"eventCount\":" ++ toString value.eventCount ++
    ",\"hostImports\":" ++ strings value.hostImports ++
    ",\"features\":" ++ strings value.features ++ "}\n"

end ComponentManifest

structure ManifestInput where
  sourceName : String
  generatedName : String
  valueType : RuntimeTypeId
deriving Repr, BEq

/-- Deterministic metadata beside each generated JavaScript module. -/
structure ArtifactManifest where
  compilerVersion : String
  leanToolchain : String
  moduleName : String
  runtimeAbi : Nat
  exportName : String
  inputs : Array ManifestInput
  resultType : RuntimeTypeId
  features : Array String
deriving Repr, BEq

namespace ArtifactManifest

def scalar (moduleName : String) (emitted : Scalar.Emitted) : ArtifactManifest :=
  { compilerVersion := LeanRx.version
    leanToolchain := LeanRx.leanToolchain
    moduleName
    runtimeAbi := LeanRx.runtimeAbi
    exportName := emitted.exportName.raw
    inputs := (emitted.inputs.toList.zip emitted.inputNames.toList |>.map fun (spec, name) =>
      { sourceName := spec.name, generatedName := name.raw, valueType := spec.valueType }).toArray
    resultType := emitted.resultType
    features := #["scalar"] }

private def quoted (value : String) : String := Js.Printer.stringLiteral value

private def inputJson (value : ManifestInput) : String :=
  "{\"name\":" ++ quoted value.sourceName ++
    ",\"generatedName\":" ++ quoted value.generatedName ++
    ",\"type\":" ++ quoted value.valueType.debug ++ "}"

/-- Stable compact JSON; field and array order are deliberately fixed. -/
def json (value : ArtifactManifest) : String :=
  "{\"compilerVersion\":" ++ quoted value.compilerVersion ++
    ",\"leanToolchain\":" ++ quoted value.leanToolchain ++
    ",\"module\":" ++ quoted value.moduleName ++
    ",\"runtimeAbi\":" ++ toString value.runtimeAbi ++
    ",\"exports\":[" ++ quoted value.exportName ++ "]" ++
    ",\"inputs\":[" ++ String.intercalate "," (value.inputs.toList.map inputJson) ++ "]" ++
    ",\"resultType\":" ++ quoted value.resultType.debug ++
    ",\"features\":[" ++ String.intercalate "," (value.features.toList.map quoted) ++ "]}\n"

end ArtifactManifest

end LeanRx.Backend
