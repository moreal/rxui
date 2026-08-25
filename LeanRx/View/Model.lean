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

/-- Sealed staged expression over one region's row fields (ADR-0043). The
language mirrors the shape of `RxExpr` without touching it: `String`-only,
no dependency sets, no schema — a row expression can never observe component
state. Field references are positional projections of the row tuple and are
bounds-checked by `ComponentSpec.check`. -/
inductive RowExpr where
  | lit (value : String)
  | field (index : Nat)
  | append (first second : RowExpr)
deriving Repr, BEq, DecidableEq

/-- Every row field index one row expression projects. -/
def RowExpr.fieldRefs : RowExpr → List Nat
  | .lit _ => []
  | .field index => [index]
  | .append first second => first.fieldRefs ++ second.fieldRefs

/-- Closed row action vocabulary for keyed region rows (ADR-0041/0043).
`remove` disposes the dispatching row; `update` writes new field values —
sealed row expressions evaluated simultaneously against the dispatching row's
current fields — and re-renders exactly that row through the region handle's
`updateAt`. The sealed constructor set is the whole semantics — row events
never carry user update programs. -/
inductive RowAction where
  | remove
  | update (assignments : List (Nat × RowExpr))
deriving Repr, BEq, DecidableEq

def RowAction.name : RowAction → String
  | .remove => "remove"
  | .update _ => "update"

/-- One declared row event of a keyed region. The name is what row templates
bind with `onClick={…}` and what the delegated dispatcher receives as its
action string. -/
structure RowEventSpec where
  name : String
  action : RowAction
  span : SourceSpan := .generated
deriving Repr, BEq

/-- One sealed row-scoped class selection (ADR-0044): the element's `class`
attribute is `whenTrue` while the projected row field equals the comparison
literal and `whenFalse` otherwise. Both class values, the attribute name, and
the predicate shape are fixed at elaboration time; the retained-row update
callback re-emits the selection so it tracks ADR-0043 row field updates. -/
structure RowClassSelect where
  field : Nat
  equals : String
  whenTrue : String
  whenFalse : String
  span : SourceSpan := .generated
deriving Repr, BEq

/- Sealed row template of a keyed region (ADR-0041/0043/0044). Dynamic row
content is a typed projection of the row tuple (`fieldText`) or a sealed row
expression over it (`exprText`), never an `RxExpr`; row events reference the
region's declared row events and lower to one delegated listener per event
kind on the region container; `classIf` carries at most one sealed class
selection per element. -/
mutual
  inductive RowNode where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (events : List EventBinding)
        (children : RowChildren) (span : SourceSpan := .generated)
        (classIf : List RowClassSelect := [])
    | text (value : String) (span : SourceSpan := .generated)
    | fieldText (field : Nat) (span : SourceSpan := .generated)
    | exprText (value : RowExpr) (span : SourceSpan := .generated)

  inductive RowChildren where
    | nil
    | cons (head : RowNode) (tail : RowChildren)
end

namespace RowChildren

def ofList : List RowNode → RowChildren
  | [] => .nil
  | head :: tail => .cons head (ofList tail)

def toList : RowChildren → List RowNode
  | .nil => []
  | .cons head tail => head :: toList tail

end RowChildren

def RowNode.node (tag : HtmlTag) (children : List RowNode)
    (attrs : List StaticAttr := []) (events : List EventBinding := [])
    (span : SourceSpan := .generated) (classIf : List RowClassSelect := []) : RowNode :=
  .element tag attrs events (.ofList children) span classIf

def RowNode.nodeWith (tag : HtmlTag) (children : List RowNode)
    (attrs : List ViewAttr := []) (span : SourceSpan := .generated)
    (classIf : List RowClassSelect := []) : RowNode :=
  RowNode.node tag children (attrs := ViewAttr.staticAttrs attrs)
    (events := ViewAttr.events attrs) (span := span) (classIf := classIf)

/-- One keyed region declaration (ADR-0040/0041). Rows are tuples of `String`
fields behind a monotone region-owned key; the template is the sealed row view
instantiated per row; row events form the closed delegated vocabulary. -/
structure RegionSpec where
  name : String
  fields : Array String
  template : RowNode
  events : Array RowEventSpec
  span : SourceSpan := .generated

/- Explicit safe M4 view. Interpolation is text-only; raw HTML has no
constructor. A `child` position statically nests another checked component by
name (ADR-0039), optionally passing immutable props as name/value pairs in the
child's declaration order (ADR-0042). A `region` position mounts a declared
keyed region (ADR-0041), and `propText` renders one of this component's own
immutable props as static mount-time text. -/
mutual
  inductive View (Γ : Schema) where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (events : List EventBinding)
        (children : ViewChildren Γ) (span : SourceSpan := .generated)
        (props : List (PropBinding Γ) := [])
    | text (value : String) (span : SourceSpan := .generated)
    | scalarText (name : String) (value : RxExpr Γ deps String)
        (span : SourceSpan := .generated)
    | child (name : String) (span : SourceSpan := .generated)
        (props : List (String × String) := [])
    | region (name : String) (span : SourceSpan := .generated)
    | propText (field : Nat) (span : SourceSpan := .generated)

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
  | .child name existing props =>
      .child name (if existing.file.isEmpty then span else existing) props
  | .region name existing => .region name (if existing.file.isEmpty then span else existing)
  | .propText field existing =>
      .propText field (if existing.file.isEmpty then span else existing)

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
child position names the statically nested component mounted there together
with the prop values it receives; a region position names the keyed region
mounted there; a prop text position renders one own immutable prop. -/
mutual
  inductive MountNode where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (children : MountChildren)
    | text (value : String)
    | dynamicText
    | child (name : String) (propValues : List String := [])
    | region (name : String)
    | propText (field : Nat)

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
  props : List (String × String) := []
deriving Repr, BEq

structure MountedRegion where
  path : List Nat
  name : String
  span : SourceSpan
deriving Repr, BEq

structure MountedPropText where
  path : List Nat
  field : Nat
  span : SourceSpan
deriving Repr, BEq

structure ViewSplit (Γ : Schema) where
  template : MountNode
  textSinks : List (TextSink Γ)
  events : List MountedEvent
  props : List (MountedProp Γ) := []
  childRefs : List MountedChild := []
  regionRefs : List MountedRegion := []
  propTexts : List MountedPropText := []

mutual
  private def View.mountNode : View Γ → MountNode
    | .element tag attrs _ children _ _ => .element tag attrs (children.mountChildren)
    | .text value _ => .text value
    | .scalarText _ _ _ => .dynamicText
    | .child name _ props => .child name (props.map (·.2))
    | .region name _ => .region name
    | .propText field _ => .propText field

  private def ViewChildren.mountChildren : ViewChildren Γ → MountChildren
    | .nil => .nil
    | .cons head tail => .cons head.mountNode tail.mountChildren
end

mutual
  private def View.textSinksAt (path : List Nat) : View Γ → List (TextSink Γ)
    | .element _ _ _ children _ _ => children.textSinksAt path 0
    | .text _ _ | .child _ _ _ | .region _ _ | .propText _ _ => []
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
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .region _ _ | .propText _ _ => []

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
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .region _ _ | .propText _ _ => []

  private def ViewChildren.propsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List (MountedProp Γ)
    | .nil => []
    | .cons head tail =>
        head.propsAt (path ++ [index]) ++ tail.propsAt path (index + 1)
end

mutual
  private def View.childRefsAt (path : List Nat) : View Γ → List MountedChild
    | .element _ _ _ children _ _ => children.childRefsAt path 0
    | .text _ _ | .scalarText _ _ _ | .region _ _ | .propText _ _ => []
    | .child name span props => [{ path, name, span, props }]

  private def ViewChildren.childRefsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedChild
    | .nil => []
    | .cons head tail =>
        head.childRefsAt (path ++ [index]) ++ tail.childRefsAt path (index + 1)
end

mutual
  private def View.regionRefsAt (path : List Nat) : View Γ → List MountedRegion
    | .element _ _ _ children _ _ => children.regionRefsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .propText _ _ => []
    | .region name span => [{ path, name, span }]

  private def ViewChildren.regionRefsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedRegion
    | .nil => []
    | .cons head tail =>
        head.regionRefsAt (path ++ [index]) ++ tail.regionRefsAt path (index + 1)
end

mutual
  private def View.propTextsAt (path : List Nat) : View Γ → List MountedPropText
    | .element _ _ _ children _ _ => children.propTextsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .region _ _ => []
    | .propText field span => [{ path, field, span }]

  private def ViewChildren.propTextsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedPropText
    | .nil => []
    | .cons head tail =>
        head.propTextsAt (path ++ [index]) ++ tail.propTextsAt path (index + 1)
end

/-- Purely split a safe view into its mount tree, scalar sinks, event bindings,
reflected properties, nested component references, keyed region slots, and
immutable prop text positions. -/
def View.split (value : View Γ) : ViewSplit Γ :=
  { template := value.mountNode
    textSinks := value.textSinksAt []
    events := value.eventsAt []
    props := value.propsAt []
    childRefs := value.childRefsAt []
    regionRefs := value.regionRefsAt []
    propTexts := value.propTextsAt [] }

end LeanRx
