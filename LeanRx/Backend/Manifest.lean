import LeanRx.Backend.Scalar
import LeanRx.Backend.JsPrinter
import LeanRx.Core.Version
import LeanRx.Effect.Model

namespace LeanRx.Backend

/-- Component state-slot metadata. The scalar/vector/Fin cases mirror sealed
runtime codes; `record` and `list` are manifest-only layout descriptions owned
by specialized checked backends and never enter graph equality validation. -/
inductive ManifestTypeId where
  | bool
  | string
  | int
  | nat
  | vector (element : ManifestTypeId) (length : Nat)
  | fin (bound : Nat)
  | record (name : String)
  | list (element : ManifestTypeId)
deriving Repr, BEq, DecidableEq

def ManifestTypeId.ofRuntime : RuntimeTypeId → ManifestTypeId
  | .bool => .bool
  | .string => .string
  | .int => .int
  | .nat => .nat
  | .vector element length => .vector (ofRuntime element) length
  | .fin bound => .fin bound

def ManifestTypeId.debug : ManifestTypeId → String
  | .bool => "bool"
  | .string => "string"
  | .int => "int"
  | .nat => "nat"
  | .vector element length => s!"vector<{element.debug},{length}>"
  | .fin bound => s!"fin<{bound}>"
  | .record name => s!"record<{name}>"
  | .list element => s!"list<{element.debug}>"

/-- Deterministic disclosure of a foreign boundary consumed by a generated
component. This is manifest metadata, not a reactive runtime type. -/
structure PortManifest where
  name : String
  inputType : Effect.PortTypeId
  outputType : Effect.PortTypeId
  mode : Effect.PortMode
  cancellation : Effect.PortCancellation
  errors : Array String
  trust : String
  security : String
deriving Repr, BEq

namespace PortManifest

def ofForeign (port : Effect.ForeignPort ι ο) : PortManifest := {
  name := port.name
  inputType := port.inputType
  outputType := port.outputType
  mode := port.mode
  cancellation := port.cancellation
  errors := port.errors
  trust := port.trust
  security := port.security
}

end PortManifest

structure ComponentManifest where
  compilerVersion : String
  leanToolchain : String
  moduleName : String
  graphHash : String
  runtimeAbi : Nat
  exports : Array String
  stateSlots : Array ManifestTypeId
  sourceCount : Nat
  derivedCount : Nat
  textSinkCount : Nat
  eventCount : Nat
  hostImports : Array String
  ports : Array PortManifest := #[]
  features : Array String
deriving Repr, BEq

namespace ComponentManifest

private def quoted (value : String) : String := Js.Printer.stringLiteral value

private def strings (values : Array String) : String :=
  "[" ++ String.intercalate "," (values.toList.map quoted) ++ "]"

private def types (values : Array ManifestTypeId) : String :=
  strings (values.map (·.debug))

private def portJson (value : PortManifest) : String :=
  "{\"name\":" ++ quoted value.name ++
    ",\"input\":" ++ quoted value.inputType.debug ++
    ",\"output\":" ++ quoted value.outputType.debug ++
    ",\"mode\":" ++ quoted value.mode.debug ++
    ",\"cancellation\":" ++ quoted value.cancellation.debug ++
    ",\"errors\":" ++ strings value.errors ++
    ",\"trust\":" ++ quoted value.trust ++
    ",\"security\":" ++ quoted value.security ++ "}"

private def portListJson (values : Array PortManifest) : String :=
  "[" ++ String.intercalate "," (values.toList.map portJson) ++ "]"

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
    ",\"ports\":" ++ portListJson value.ports ++
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
