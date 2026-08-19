import LeanRx.Cli.AtomicOutput
import LeanRx.Cli.Model
import examples.CounterBuild

namespace LeanRx.Cli.Driver

open LeanRxExamples.Counter

private def knownModule (moduleName : String) : Bool :=
  moduleName == "Examples.Counter"

private def unknownModule (moduleName : String) : IO UInt32 := do
  IO.eprintln s!"error[LRX-ELAB-020]: unknown component module {moduleName}"
  pure 1

private def componentError (error : ComponentError) : IO UInt32 := do
  IO.eprintln error.render
  pure 1

/-- `check` runs every pure backend validity phase without writing artifacts. -/
def checkBackend (checked : CheckedComponent CounterSchema) : Except Js.Error Unit := do
  let emitted ← Backend.Component.emit "Counter.mjs" checked
  let _ ← Js.Printer.module .readable emitted.module
  let _ ← Js.Printer.module .compact emitted.module

private def checkCounter (checked : CheckedComponent CounterSchema) : IO UInt32 :=
  match checkBackend checked with
  | .error error => do
      IO.eprintln s!"error[{error.code}]: {error.message}"
      pure 1
  | .ok _ => do
      IO.println s!"Examples.Counter: ok ({checked.graph.graph.nodes.size} nodes)"
      pure 0

private def graphCounter (format : Cli.GraphFormat)
    (checked : CheckedComponent CounterSchema) : IO UInt32 := do
  IO.println <| match format with
    | .json => checked.graph.toJson
    | .dot => checked.graph.toDot
  pure 0

private def runKnown : Cli.Command → IO UInt32
  | .check moduleName =>
      if knownModule moduleName then
        match CounterSyntax_check with
        | .ok checked => checkCounter checked
        | .error error => componentError error
      else unknownModule moduleName
  | .graph moduleName format =>
      if knownModule moduleName then
        match CounterSyntax_check with
        | .ok checked => graphCounter format checked
        | .error error => componentError error
      else unknownModule moduleName
  | .build moduleName output =>
      if knownModule moduleName then do
        LeanRxExamples.CounterBuild.generate ⟨output⟩
        IO.println s!"Examples.Counter: built {output}"
        pure 0
      else unknownModule moduleName

def run (args : List String) : IO UInt32 :=
  match Cli.parse args with
  | .ok command => runKnown command
  | .error error => do
      IO.eprintln s!"error[{error.code}]: {error.message}"
      pure 2

end LeanRx.Cli.Driver
