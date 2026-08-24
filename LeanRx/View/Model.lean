import LeanRx.Core.Expr
import LeanRx.Core.SourceInfo

namespace LeanRx

/-- Closed element whitelist. Arbitrary tag text never reaches the emitter. -/
inductive HtmlTag where
  | main | div | button | p | span | h1
  | h2 | h3 | header | footer | section | nav | ul | li | input | label | strong | em
  | form
deriving Repr, BEq, DecidableEq

def HtmlTag.name : HtmlTag → String
  | .main => "main"
  | .div => "div"
  | .button => "button"
  | .p => "p"
  | .span => "span"
  | .h1 => "h1"
  | .h2 => "h2"
  | .h3 => "h3"
  | .header => "header"
  | .footer => "footer"
  | .section => "section"
  | .nav => "nav"
  | .ul => "ul"
  | .li => "li"
  | .input => "input"
  | .label => "label"
  | .strong => "strong"
  | .em => "em"
  | .form => "form"

inductive ButtonType where
  | button | submit | reset
deriving Repr, BEq, DecidableEq

def ButtonType.name : ButtonType → String
  | .button => "button"
  | .submit => "submit"
  | .reset => "reset"

/-- Closed input control types supported by the safe view. -/
inductive InputType where
  | text | checkbox
deriving Repr, BEq, DecidableEq

def InputType.name : InputType → String
  | .text => "text"
  | .checkbox => "checkbox"

/-- Safe, context-specific static attributes supported in the safe view. -/
inductive StaticAttr where
  | className (value : String)
  | id (value : String)
  | ariaLabel (value : String)
  | buttonType (value : ButtonType)
  | inputType (value : InputType)
  | role (value : String)
  | placeholder (value : String)
deriving Repr, BEq

def StaticAttr.name : StaticAttr → String
  | .className _ => "class"
  | .id _ => "id"
  | .ariaLabel _ => "aria-label"
  | .buttonType _ => "type"
  | .inputType _ => "type"
  | .role _ => "role"
  | .placeholder _ => "placeholder"

def StaticAttr.value : StaticAttr → String
  | .className value | .id value | .ariaLabel value | .role value
  | .placeholder value => value
  | .buttonType value => value.name
  | .inputType value => value.name

inductive EventKind where
  | click
  | dblclick
  | input
  | keydown
  | change
  | checkedChange
  | submit
deriving Repr, BEq, DecidableEq

def EventKind.name : EventKind → String
  | .click => "click"
  | .dblclick => "dblclick"
  | .input => "input"
  | .keydown => "keydown"
  | .change | .checkedChange => "change"
  | .submit => "submit"

/-- Host payload class of one event kind. Payload-carrying kinds must bind a
typed event and mount through the form-event host adapters. -/
inductive EventPayload where
  | none
  | value
  | key
  | checked
deriving Repr, BEq, DecidableEq

def EventKind.payload : EventKind → EventPayload
  | .click | .dblclick | .submit => .none
  | .input | .change => .value
  | .keydown => .key
  | .checkedChange => .checked

structure EventBinding where
  kind : EventKind
  eventName : String
  span : SourceSpan := .generated
deriving Repr, BEq

/-- One reflected DOM property (ADR-0038). The constructor fixes both the
compiler-owned property name and the only expression type it accepts, so a
`checked` reflection can never receive a string and property names never come
from user text. -/
inductive PropBinding (Γ : Schema) where
  | value (expr : RxExpr Γ deps String) (span : SourceSpan := .generated)
  | checked (expr : RxExpr Γ deps Bool) (span : SourceSpan := .generated)

namespace PropBinding

def name : PropBinding Γ → String
  | .value .. => "value"
  | .checked .. => "checked"

def valueType : PropBinding Γ → RuntimeTypeId
  | .value .. => .string
  | .checked .. => .bool

def dependencyIds : PropBinding Γ → List Nat
  | .value expr _ | .checked expr _ => expr.dependencies.ids

def debug : PropBinding Γ → String
  | .value expr _ | .checked expr _ => "rx:" ++ expr.debug

def span : PropBinding Γ → SourceSpan
  | .value _ span | .checked _ span => span

end PropBinding

/-- Unified surface attribute; validation still separates static attributes from events. -/
inductive ViewAttr where
  | static (value : StaticAttr)
  | event (value : EventBinding)
deriving Repr, BEq

namespace ViewAttr

def staticAttrs : List ViewAttr → List StaticAttr
  | [] => []
  | .static value :: rest => value :: staticAttrs rest
  | .event _ :: rest => staticAttrs rest

def events : List ViewAttr → List EventBinding
  | [] => []
  | .static _ :: rest => events rest
  | .event value :: rest => value :: events rest

end ViewAttr

/- Explicit safe M4 view. Interpolation is text-only; raw HTML has no
constructor. A `child` position statically nests another checked component by
name (ADR-0039); the parent's `ComponentSpec.children` table must declare it. -/
mutual
  inductive View (Γ : Schema) where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (events : List EventBinding)
        (children : ViewChildren Γ) (span : SourceSpan := .generated)
        (props : List (PropBinding Γ) := [])
    | text (value : String) (span : SourceSpan := .generated)
    | scalarText (name : String) (value : RxExpr Γ deps String)
        (span : SourceSpan := .generated)
    | child (name : String) (span : SourceSpan := .generated)

  inductive ViewChildren (Γ : Schema) where
    | nil
    | cons (head : View Γ) (tail : ViewChildren Γ)
end

namespace ViewChildren

def ofList : List (View Γ) → ViewChildren Γ
  | [] => .nil
  | head :: tail => .cons head (ofList tail)

end ViewChildren

namespace View

def withSpan (view : View Γ) (span : SourceSpan) : View Γ :=
  match view with
  | .element tag attrs events children existing props =>
      .element tag attrs events children (if existing.file.isEmpty then span else existing) props
  | .text value existing => .text value (if existing.file.isEmpty then span else existing)
  | .scalarText name value existing =>
      .scalarText name value (if existing.file.isEmpty then span else existing)
  | .child name existing => .child name (if existing.file.isEmpty then span else existing)

def node (tag : HtmlTag) (children : List (View Γ))
    (attrs : List StaticAttr := []) (events : List EventBinding := [])
    (span : SourceSpan := .generated) (props : List (PropBinding Γ) := []) : View Γ :=
  .element tag attrs events (.ofList children) span props

def nodeWith (tag : HtmlTag) (children : List (View Γ))
    (attrs : List ViewAttr := []) (span : SourceSpan := .generated)
    (props : List (PropBinding Γ) := []) : View Γ :=
  node tag children (attrs := ViewAttr.staticAttrs attrs)
    (events := ViewAttr.events attrs) (span := span) (props := props)

end View

/- Static mount tree. Dynamic text positions are placeholders, never HTML; a
child position names the statically nested component mounted there. -/
mutual
  inductive MountNode where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (children : MountChildren)
    | text (value : String)
    | dynamicText
    | child (name : String)

  inductive MountChildren where
    | nil
    | cons (head : MountNode) (tail : MountChildren)
end

structure TextSink (Γ : Schema) where
  deps : DepSet Γ
  name : String
  path : List Nat
  value : RxExpr Γ deps String
  span : SourceSpan

structure MountedEvent where
  path : List Nat
  binding : EventBinding
deriving Repr, BEq

structure MountedProp (Γ : Schema) where
  path : List Nat
  binding : PropBinding Γ

structure MountedChild where
  path : List Nat
  name : String
  span : SourceSpan
deriving Repr, BEq

structure ViewSplit (Γ : Schema) where
  template : MountNode
  textSinks : List (TextSink Γ)
  events : List MountedEvent
  props : List (MountedProp Γ) := []
  childRefs : List MountedChild := []

mutual
  private def View.mountNode : View Γ → MountNode
    | .element tag attrs _ children _ _ => .element tag attrs (children.mountChildren)
    | .text value _ => .text value
    | .scalarText _ _ _ => .dynamicText
    | .child name _ => .child name

  private def ViewChildren.mountChildren : ViewChildren Γ → MountChildren
    | .nil => .nil
    | .cons head tail => .cons head.mountNode tail.mountChildren
end

mutual
  private def View.textSinksAt (path : List Nat) : View Γ → List (TextSink Γ)
    | .element _ _ _ children _ _ => children.textSinksAt path 0
    | .text _ _ | .child _ _ => []
    | .scalarText name value span =>
        [{ deps := value.dependencies, name, path, value, span }]

  private def ViewChildren.textSinksAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List (TextSink Γ)
    | .nil => []
    | .cons head tail =>
        head.textSinksAt (path ++ [index]) ++ tail.textSinksAt path (index + 1)
end

mutual
  private def View.eventsAt (path : List Nat) : View Γ → List MountedEvent
    | .element _ _ bindings children _ _ =>
        bindings.map (fun binding => { path, binding }) ++ children.eventsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ => []

  private def ViewChildren.eventsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedEvent
    | .nil => []
    | .cons head tail =>
        head.eventsAt (path ++ [index]) ++ tail.eventsAt path (index + 1)
end

mutual
  private def View.propsAt (path : List Nat) : View Γ → List (MountedProp Γ)
    | .element _ _ _ children _ props =>
        props.map (fun binding => { path, binding }) ++ children.propsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ => []

  private def ViewChildren.propsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List (MountedProp Γ)
    | .nil => []
    | .cons head tail =>
        head.propsAt (path ++ [index]) ++ tail.propsAt path (index + 1)
end

mutual
  private def View.childRefsAt (path : List Nat) : View Γ → List MountedChild
    | .element _ _ _ children _ _ => children.childRefsAt path 0
    | .text _ _ | .scalarText _ _ _ => []
    | .child name span => [{ path, name, span }]

  private def ViewChildren.childRefsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedChild
    | .nil => []
    | .cons head tail =>
        head.childRefsAt (path ++ [index]) ++ tail.childRefsAt path (index + 1)
end

/-- Purely split a safe view into its mount tree, scalar sinks, event bindings,
reflected properties, and nested component references. -/
def View.split (value : View Γ) : ViewSplit Γ :=
  { template := value.mountNode
    textSinks := value.textSinksAt []
    events := value.eventsAt []
    props := value.propsAt []
    childRefs := value.childRefsAt [] }

end LeanRx
