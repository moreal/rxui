import LeanRx.Cli.Model

namespace LeanRxTest.Cli.Model

open LeanRx.Cli

def run : IO Unit := do
  match parse ["check", "Examples.Counter"] with
  | .ok (.check "Examples.Counter") => pure ()
  | _ => throw <| IO.userError "CLI check parsing changed"
  match parse ["graph", "Examples.Counter", "--format", "json"] with
  | .ok (.graph "Examples.Counter" .json) => pure ()
  | _ => throw <| IO.userError "CLI graph parsing changed"
  match parse ["graph", "Examples.Counter", "--format", "dot"] with
  | .ok (.graph "Examples.Counter" .dot) => pure ()
  | _ => throw <| IO.userError "CLI DOT parsing changed"
  match parse ["graph", "Examples.Counter", "--format", "html"] with
  | .ok (.graph "Examples.Counter" .html) => pure ()
  | _ => throw <| IO.userError "CLI HTML graph parsing changed"
  match parse ["build", "Examples.Counter", "--out", "dist"] with
  | .ok (.build "Examples.Counter" "dist") => pure ()
  | _ => throw <| IO.userError "CLI build parsing changed"
  match parse ["scaffold", "--out", "starter"] with
  | .ok (.scaffold "starter") => pure ()
  | _ => throw <| IO.userError "CLI scaffold parsing changed"
  match parse ["explain", "LRX-TYPE-108"] with
  | .ok (.explain "LRX-TYPE-108") => pure ()
  | _ => throw <| IO.userError "CLI explain parsing changed"
  match parse ["doctor"] with
  | .ok .doctor => pure ()
  | _ => throw <| IO.userError "CLI doctor parsing changed"
  match explanation? "LRX-TYPE-108" with
  | some value =>
      unless value.phase == "typed component validation" &&
          value.render.contains "transaction barrier" do
        throw <| IO.userError "diagnostic explanation changed"
  | none => throw <| IO.userError "known diagnostic explanation disappeared"
  unless (explanation? "LRX-UNKNOWN-999").isNone do
    throw <| IO.userError "unknown diagnostic acquired a guessed explanation"
  match parse ["build", "Examples.Counter"] with
  | .ok _ => throw <| IO.userError "incomplete CLI build was accepted"
  | .error error =>
      unless error.code == "LRX-SYN-001" do
        throw <| IO.userError "CLI parse error code changed"

end LeanRxTest.Cli.Model
