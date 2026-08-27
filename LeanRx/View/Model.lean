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
bounds-checked by `ComponentSpec.check`. `payload` references the dispatching
typed row event's `String` payload (ADR-0046) and is valid only in the
right-hand sides of a payload-taking row event. `trim` is the sealed
whitespace-trim unary (ADR-0054): ASCII whitespace stripped from both ends,
the one string normalization the TodoMVC commit contract needs — not a
general string-function vocabulary. -/
inductive RowExpr where
  | lit (value : String)
  | field (index : Nat)
  | payload
  | append (first second : RowExpr)
  | trim (value : RowExpr)
deriving Repr, BEq, DecidableEq

/-- Every row field index one row expression projects. -/
def RowExpr.fieldRefs : RowExpr → List Nat
  | .lit _ | .payload => []
  | .field index => [index]
  | .append first second => first.fieldRefs ++ second.fieldRefs
  | .trim value => value.fieldRefs

/-- Whether the expression references the dispatching event's payload
(ADR-0046). Payload references are rejected outside typed row event
right-hand sides. -/
def RowExpr.hasPayload : RowExpr → Bool
  | .lit _ | .field _ => false
  | .payload => true
  | .append first second => first.hasPayload || second.hasPayload
  | .trim value => value.hasPayload

/-- Whether the expression uses the ADR-0054 trim unary, for the manifest
feature stamp. -/
def RowExpr.hasTrim : RowExpr → Bool
  | .lit _ | .field _ | .payload => false
  | .append first second => first.hasTrim || second.hasTrim
  | .trim _ => true

/-- The single projected field of a sealed guard subject (ADR-0053/0054): a
guard compares one row field — raw or behind the one trim unary — against
its literal. Any other expression shape is not a guard subject. -/
def RowExpr.guardSubject? : RowExpr → Option Nat
  | .field index => some index
  | .trim (.field index) => some index
  | _ => none

/-- One sealed row-field guard (ADR-0053): equality of a single projected row
field against one string literal — the empty string for TodoMVC's
destroy-on-empty-commit. The subject is a sealed row expression restricted by
`ComponentSpec.check` to one field projection, optionally behind the ADR-0054
trim unary; the guard shape itself is the whole predicate language: no
negation, no conjunction, no payload reference, and no component state. -/
structure RowGuard where
  value : RowExpr
  equals : String
deriving Repr, BEq, DecidableEq

/-- One sealed row update stage (ADR-0043/0053): simultaneous assignments
evaluated against the dispatching row's current fields. `removeIf` is the
optional ADR-0053 guard — when the guarded field equals its literal the
dispatching row is removed instead and no assignment runs; otherwise the
assignments commit as one retained-row update. The stage shape is shared by
the plain update action and every ADR-0052 key arm, and the guard equality
runs inside the generated dispatch function — no host change. -/
structure RowStage where
  assignments : List (Nat × RowExpr)
  removeIf : Option RowGuard := none
deriving Repr, BEq, DecidableEq

/-- Closed row action vocabulary for keyed region rows (ADR-0041/0043).
`remove` disposes the dispatching row; `update` runs one sealed row stage —
simultaneous assignments, optionally guarded by the ADR-0053 remove-if
equality — and re-renders exactly that row through the region handle's
`updateAt`. `keySelect` branches a keydown row event on its delegated `key`
payload (ADR-0052): each arm maps one sealed key literal to a row stage, a
non-matching key is a no-op, and the equality runs inside the generated
dispatch function — no host change. The sealed constructor set is the whole
semantics — row events never carry user update programs. -/
inductive RowAction where
  | remove
  | update (stage : RowStage)
  | keySelect (arms : List (String × RowStage))
deriving Repr, BEq, DecidableEq

def RowAction.name : RowAction → String
  | .remove => "remove"
  | .update _ => "update"
  | .keySelect _ => "keySelect"

/-- The sealed key literals a key-branched row event may compare against
(ADR-0052): the two keys the TodoMVC editor contract branches on. Growing the
set is a vocabulary decision, not a template freedom. -/
def RowAction.keyLiterals : List String := ["Enter", "Escape"]

/-- Whether the action is the ADR-0052 key-branched selection, for the
keydown-only binding rule. -/
def RowAction.isKeySelect : RowAction → Bool
  | .keySelect _ => true
  | .remove | .update _ => false

/-- Whether any stage of the action carries the ADR-0053 remove-if guard,
for the manifest feature stamp. -/
def RowAction.hasGuard : RowAction → Bool
  | .remove => false
  | .update stage => stage.removeIf.isSome
  | .keySelect arms => arms.any (·.2.removeIf.isSome)

/-- Whether any row expression of the stage — assignment right-hand side or
guard subject — uses the ADR-0054 trim unary, for the manifest feature
stamp. -/
def RowStage.hasTrim (stage : RowStage) : Bool :=
  stage.assignments.any (·.2.hasTrim) ||
    (stage.removeIf.map (·.value.hasTrim)).getD false

/-- Whether any stage of the action uses the ADR-0054 trim unary, for the
manifest feature stamp. -/
def RowAction.hasTrim : RowAction → Bool
  | .remove => false
  | .update stage => stage.hasTrim
  | .keySelect arms => arms.any (·.2.hasTrim)

/-- One declared row event of a keyed region. The name is what row templates
bind with `onClick={…}`/`onDblClick={…}` (or, for payload-taking events,
`onInput={…}`/`onKeyDown={…}`/`onChange={…}` — ADR-0046/0049) and what the
delegated dispatcher receives as its action string. `takesPayload` marks a
typed row event whose update right-hand sides may reference the delegated
`String` payload; the template binding kind selects between the delegated
`value`, `key`, and `"true"`/`"false"`-lowered `checked` payloads. -/
structure RowEventSpec where
  name : String
  action : RowAction
  takesPayload : Bool := false
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

/-- One sealed state-scoped attribute selection on a static view element
(ADR-0045): the element's attribute follows equality of one `String`
component value (source or derived) against one string literal, joining the
commit sweep beside text sinks and reflected properties with the same
evaluate-compare-write shape. The attribute vocabulary is compiler-owned and
closed: `class` selects between two static class strings, `aria-pressed`
reflects the equality as `"true"`/`"false"`, and `disabled` reflects it as
the boolean element property (a `disabled` attribute cannot be cleared by
assignment, so the property write reuses the existing `setProperty` host
export). The typed `Field Γ String` makes cross-typed predicates
unrepresentable. The subject may sit behind the one sealed ADR-0054/0055
trim unary (`trimmed`, ADR-0057): the sweep then compares the
ASCII-trimmed field value against the literal — the exact equality the
ADR-0055 skip guard evaluates — so an affordance can agree with a
dispatch-layer guard by construction. General predicates, negation, and
composed subjects stay unrepresentable. -/
inductive AttrSelect (Γ : Schema) where
  | classSelect (field : Field Γ String) (equals whenTrue whenFalse : String)
      (span : SourceSpan := .generated) (trimmed : Bool := false)
  | pressedSelect (field : Field Γ String) (equals : String)
      (span : SourceSpan := .generated) (trimmed : Bool := false)
  | disabledSelect (field : Field Γ String) (equals : String)
      (span : SourceSpan := .generated) (trimmed : Bool := false)

namespace AttrSelect

def name : AttrSelect Γ → String
  | .classSelect .. => "class"
  | .pressedSelect .. => "aria-pressed"
  | .disabledSelect .. => "disabled"

def fieldIndex : AttrSelect Γ → Nat
  | .classSelect field .. | .pressedSelect field ..
  | .disabledSelect field .. => field.index

def equals : AttrSelect Γ → String
  | .classSelect _ equals .. | .pressedSelect _ equals ..
  | .disabledSelect _ equals .. => equals

/-- Whether the subject sits behind the sealed trim unary (ADR-0057). -/
def trimmed : AttrSelect Γ → Bool
  | .classSelect _ _ _ _ _ trimmed | .pressedSelect _ _ _ trimmed
  | .disabledSelect _ _ _ trimmed => trimmed

/-- The written value type: `disabled` writes a boolean property; the other
selections write attribute strings. -/
def valueType : AttrSelect Γ → RuntimeTypeId
  | .classSelect .. | .pressedSelect .. => .string
  | .disabledSelect .. => .bool

def span : AttrSelect Γ → SourceSpan
  | .classSelect _ _ _ _ span _ | .pressedSelect _ _ span _
  | .disabledSelect _ _ span _ => span

def debug (select : AttrSelect Γ) : String :=
  s!"select:{select.name}:{if select.trimmed then "trim:" else ""}{select.fieldIndex}"

end AttrSelect

/-- Sealed reflected row property target (ADR-0047/0049). `value` writes the
row expression string into the input's `value` property; `checkedIf equals`
writes the boolean equality of the row expression against the literal into a
checkbox input's `checked` property — the ADR-0045 `disabled` precedent
carried into row scope, so the toggle state survives the retained-row update
sweep. -/
inductive RowReflectTarget where
  | value
  | checkedIf (equals : String)
deriving Repr, BEq, DecidableEq

def RowReflectTarget.propertyName : RowReflectTarget → String
  | .value => "value"
  | .checkedIf _ => "checked"

/-- One sealed row-scoped property reflection (ADR-0047/0049): the input
element's `value` (or checkbox `checked`) property follows the sealed row
expression on mount and inside the retained-row update callback. The property
name is compiler-owned (fixed by `RowReflectTarget`) and the write reuses the
existing `setProperty` host export; because a row update driven by the
input's own typed payload writes the state the input already holds, the
WHATWG equal-value assignment is a caret no-op (ADR-0038's controlled-input
finding, reused in row scope). -/
structure RowReflect where
  value : RowExpr
  target : RowReflectTarget := .value
  span : SourceSpan := .generated
deriving Repr, BEq

/- Sealed row template of a keyed region (ADR-0041/0043/0044/0047/0048).
Dynamic row content is a typed projection of the row tuple (`fieldText`) or a
sealed row expression over it (`exprText`), never an `RxExpr`; row events
reference the region's declared row events and lower to one delegated
listener per event kind on the region container; `classIf` carries at most
one sealed class selection per element and `reflects` at most one sealed
reflection per input element and property target (ADR-0047/0049). A `branch` node is the sealed
two-branch row cell (ADR-0047): it may sit only at a cell position (direct
child of the row root), both subtrees are fixed at elaboration, the mounted
branch follows equality of one projected row field against one literal, and
the retained-row update callback replaces the cell's subtree only on a
branch change. `autoFocus` is the sealed focus marker (ADR-0048): inputs
inside branch subtrees only, at most one per subtree, honored exclusively by
the update callback's replacement arm — row mount never focuses. -/
mutual
  inductive RowNode where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (events : List EventBinding)
        (children : RowChildren) (span : SourceSpan := .generated)
        (classIf : List RowClassSelect := []) (reflects : List RowReflect := [])
        (autoFocus : Bool := false)
    | text (value : String) (span : SourceSpan := .generated)
    | fieldText (field : Nat) (span : SourceSpan := .generated)
    | exprText (value : RowExpr) (span : SourceSpan := .generated)
    | branch (field : Nat) (equals : String) (whenTrue whenFalse : RowNode)
        (span : SourceSpan := .generated)

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
    (span : SourceSpan := .generated) (classIf : List RowClassSelect := [])
    (reflects : List RowReflect := []) (autoFocus : Bool := false) : RowNode :=
  .element tag attrs events (.ofList children) span classIf reflects autoFocus

def RowNode.nodeWith (tag : HtmlTag) (children : List RowNode)
    (attrs : List ViewAttr := []) (span : SourceSpan := .generated)
    (classIf : List RowClassSelect := [])
    (reflects : List RowReflect := []) (autoFocus : Bool := false) : RowNode :=
  RowNode.node tag children (attrs := ViewAttr.staticAttrs attrs)
    (events := ViewAttr.events attrs) (span := span) (classIf := classIf)
    (reflects := reflects) (autoFocus := autoFocus)

/- Whether any sealed row expression of the template — `exprText` content or
a property reflection — uses the ADR-0054 trim unary, for the manifest
feature stamp. -/
mutual
  def RowNode.hasTrim : RowNode → Bool
    | .element _ _ _ children _ _ reflects _ =>
        reflects.any (·.value.hasTrim) || RowChildren.hasTrim children
    | .text _ _ | .fieldText _ _ => false
    | .exprText value _ => value.hasTrim
    | .branch _ _ whenTrue whenFalse _ =>
        RowNode.hasTrim whenTrue || RowNode.hasTrim whenFalse

  def RowChildren.hasTrim : RowChildren → Bool
    | .nil => false
    | .cons head tail => RowNode.hasTrim head || RowChildren.hasTrim tail
end

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
keyed region (ADR-0041), `regionCount` renders one sealed row aggregate — the
row count of a declared region, or the count of rows whose projected field
equals one string literal (ADR-0050) — `propText` renders one of this
component's own immutable props as static mount-time text, and `selects`
carries the element's sealed state-scoped attribute selections (ADR-0045). -/
mutual
  inductive View (Γ : Schema) where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (events : List EventBinding)
        (children : ViewChildren Γ) (span : SourceSpan := .generated)
        (props : List (PropBinding Γ) := []) (selects : List (AttrSelect Γ) := [])
    | text (value : String) (span : SourceSpan := .generated)
    | scalarText (name : String) (value : RxExpr Γ deps String)
        (span : SourceSpan := .generated)
    | child (name : String) (span : SourceSpan := .generated)
        (props : List (String × String) := [])
    | region (name : String) (span : SourceSpan := .generated)
    | regionCount (region : String) (predicate : Option (Nat × String) := none)
        (span : SourceSpan := .generated)
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
  | .element tag attrs events children existing props selects =>
      .element tag attrs events children (if existing.file.isEmpty then span else existing)
        props selects
  | .text value existing => .text value (if existing.file.isEmpty then span else existing)
  | .scalarText name value existing =>
      .scalarText name value (if existing.file.isEmpty then span else existing)
  | .child name existing props =>
      .child name (if existing.file.isEmpty then span else existing) props
  | .region name existing => .region name (if existing.file.isEmpty then span else existing)
  | .regionCount regionName predicate existing =>
      .regionCount regionName predicate (if existing.file.isEmpty then span else existing)
  | .propText field existing =>
      .propText field (if existing.file.isEmpty then span else existing)

def node (tag : HtmlTag) (children : List (View Γ))
    (attrs : List StaticAttr := []) (events : List EventBinding := [])
    (span : SourceSpan := .generated) (props : List (PropBinding Γ) := [])
    (selects : List (AttrSelect Γ) := []) : View Γ :=
  .element tag attrs events (.ofList children) span props selects

def nodeWith (tag : HtmlTag) (children : List (View Γ))
    (attrs : List ViewAttr := []) (span : SourceSpan := .generated)
    (props : List (PropBinding Γ) := [])
    (selects : List (AttrSelect Γ) := []) : View Γ :=
  node tag children (attrs := ViewAttr.staticAttrs attrs)
    (events := ViewAttr.events attrs) (span := span) (props := props)
    (selects := selects)

end View

/- Static mount tree. Dynamic text positions are placeholders, never HTML; a
child position names the statically nested component mounted there together
with the prop values it receives; a region position names the keyed region
mounted there; a count text position holds one sealed row aggregate, mounted
as `"0"` because regions mount empty by construction (ADR-0050); a prop text
position renders one own immutable prop. -/
mutual
  inductive MountNode where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (children : MountChildren)
    | text (value : String)
    | dynamicText
    | child (name : String) (propValues : List String := [])
    | region (name : String)
    | countText
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

structure MountedAttrSelect (Γ : Schema) where
  path : List Nat
  select : AttrSelect Γ

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

/-- One mounted sealed row aggregate (ADR-0050): the count of a region's rows,
optionally restricted to rows whose projected field equals the literal. -/
structure MountedRegionCount where
  path : List Nat
  region : String
  predicate : Option (Nat × String) := none
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
  attrSelects : List (MountedAttrSelect Γ) := []
  childRefs : List MountedChild := []
  regionRefs : List MountedRegion := []
  regionCounts : List MountedRegionCount := []
  propTexts : List MountedPropText := []

mutual
  private def View.mountNode : View Γ → MountNode
    | .element tag attrs _ children _ _ _ => .element tag attrs (children.mountChildren)
    | .text value _ => .text value
    | .scalarText _ _ _ => .dynamicText
    | .child name _ props => .child name (props.map (·.2))
    | .region name _ => .region name
    | .regionCount _ _ _ => .countText
    | .propText field _ => .propText field

  private def ViewChildren.mountChildren : ViewChildren Γ → MountChildren
    | .nil => .nil
    | .cons head tail => .cons head.mountNode tail.mountChildren
end

mutual
  private def View.textSinksAt (path : List Nat) : View Γ → List (TextSink Γ)
    | .element _ _ _ children _ _ _ => children.textSinksAt path 0
    | .text _ _ | .child _ _ _ | .region _ _ | .regionCount _ _ _ | .propText _ _ => []
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
    | .element _ _ bindings children _ _ _ =>
        bindings.map (fun binding => { path, binding }) ++ children.eventsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .region _ _
    | .regionCount _ _ _ | .propText _ _ => []

  private def ViewChildren.eventsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedEvent
    | .nil => []
    | .cons head tail =>
        head.eventsAt (path ++ [index]) ++ tail.eventsAt path (index + 1)
end

mutual
  private def View.propsAt (path : List Nat) : View Γ → List (MountedProp Γ)
    | .element _ _ _ children _ props _ =>
        props.map (fun binding => { path, binding }) ++ children.propsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .region _ _
    | .regionCount _ _ _ | .propText _ _ => []

  private def ViewChildren.propsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List (MountedProp Γ)
    | .nil => []
    | .cons head tail =>
        head.propsAt (path ++ [index]) ++ tail.propsAt path (index + 1)
end

mutual
  private def View.selectsAt (path : List Nat) : View Γ → List (MountedAttrSelect Γ)
    | .element _ _ _ children _ _ selects =>
        selects.map (fun select => { path, select }) ++ children.selectsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .region _ _
    | .regionCount _ _ _ | .propText _ _ => []

  private def ViewChildren.selectsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List (MountedAttrSelect Γ)
    | .nil => []
    | .cons head tail =>
        head.selectsAt (path ++ [index]) ++ tail.selectsAt path (index + 1)
end

mutual
  private def View.childRefsAt (path : List Nat) : View Γ → List MountedChild
    | .element _ _ _ children _ _ _ => children.childRefsAt path 0
    | .text _ _ | .scalarText _ _ _ | .region _ _ | .regionCount _ _ _
    | .propText _ _ => []
    | .child name span props => [{ path, name, span, props }]

  private def ViewChildren.childRefsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedChild
    | .nil => []
    | .cons head tail =>
        head.childRefsAt (path ++ [index]) ++ tail.childRefsAt path (index + 1)
end

mutual
  private def View.regionRefsAt (path : List Nat) : View Γ → List MountedRegion
    | .element _ _ _ children _ _ _ => children.regionRefsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .regionCount _ _ _
    | .propText _ _ => []
    | .region name span => [{ path, name, span }]

  private def ViewChildren.regionRefsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedRegion
    | .nil => []
    | .cons head tail =>
        head.regionRefsAt (path ++ [index]) ++ tail.regionRefsAt path (index + 1)
end

mutual
  private def View.regionCountsAt (path : List Nat) : View Γ → List MountedRegionCount
    | .element _ _ _ children _ _ _ => children.regionCountsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .region _ _ | .propText _ _ => []
    | .regionCount region predicate span => [{ path, region, predicate, span }]

  private def ViewChildren.regionCountsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedRegionCount
    | .nil => []
    | .cons head tail =>
        head.regionCountsAt (path ++ [index]) ++ tail.regionCountsAt path (index + 1)
end

mutual
  private def View.propTextsAt (path : List Nat) : View Γ → List MountedPropText
    | .element _ _ _ children _ _ _ => children.propTextsAt path 0
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .region _ _
    | .regionCount _ _ _ => []
    | .propText field span => [{ path, field, span }]

  private def ViewChildren.propTextsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedPropText
    | .nil => []
    | .cons head tail =>
        head.propTextsAt (path ++ [index]) ++ tail.propTextsAt path (index + 1)
end

/-- Purely split a safe view into its mount tree, scalar sinks, event bindings,
reflected properties, state-scoped attribute selections, nested component
references, keyed region slots, and immutable prop text positions. -/
def View.split (value : View Γ) : ViewSplit Γ :=
  { template := value.mountNode
    textSinks := value.textSinksAt []
    events := value.eventsAt []
    props := value.propsAt []
    attrSelects := value.selectsAt []
    childRefs := value.childRefsAt []
    regionRefs := value.regionRefsAt []
    regionCounts := value.regionCountsAt []
    propTexts := value.propTextsAt [] }

end LeanRx
