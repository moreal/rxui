import LeanRx.Cli.Model
import examples.CounterBuild

namespace LeanRx.Cli.Main

open LeanRxExamples.Counter

private def knownModule (moduleName : String) : Bool :=
  moduleName == "Examples.Counter"

private def unknownModule (moduleName : String) : IO UInt32 := do
  IO.eprintln s!"error[LRX-CLI-001]: unknown component module {moduleName}"
  pure 1

private def checkCounter (checked : CheckedComponent CounterSchema) : IO UInt32 := do
  IO.println s!"Examples.Counter: ok ({checked.graph.graph.nodes.size} nodes)"
  pure 0

private def graphCounter (checked : CheckedComponent CounterSchema) : IO UInt32 := do
  IO.println checked.graph.toJson
  pure 0

private def runKnown : Command → IO UInt32
  | .check moduleName =>
      if knownModule moduleName then
        match CounterSyntax_check with
        | .ok checked => checkCounter checked
        | .error error => do
            IO.eprintln s!"error[{error.code}]: {error.message}"
            pure 1
      else unknownModule moduleName
  | .graph moduleName =>
      if knownModule moduleName then
        match CounterSyntax_check with
        | .ok checked => graphCounter checked
        | .error error => do
            IO.eprintln s!"error[{error.code}]: {error.message}"
            pure 1
      else unknownModule moduleName
  | .build moduleName output =>
      if knownModule moduleName then do
        LeanRxExamples.CounterBuild.generate ⟨output⟩
        IO.println s!"Examples.Counter: built {output}"
        pure 0
      else unknownModule moduleName

def run (args : List String) : IO UInt32 :=
  match parse args with
  | .ok command => runKnown command
  | .error error => do
      IO.eprintln s!"error[{error.code}]: {error.message}"
      pure 2

end LeanRx.Cli.Main

def main (args : List String) : IO UInt32 := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  LeanRx.Cli.Main.run values
