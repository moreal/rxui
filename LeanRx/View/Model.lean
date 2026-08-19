import LeanRx.Core.Expr
import LeanRx.Core.SourceInfo

namespace LeanRx

/-- Closed M4 element whitelist. Arbitrary tag text never reaches the emitter. -/
inductive HtmlTag where
  | main | div | button | p | span | h1
deriving Repr, BEq, DecidableEq

def HtmlTag.name : HtmlTag → String
  | .main => "main"
  | .div => "div"
  | .button => "button"
  | .p => "p"
  | .span => "span"
  | .h1 => "h1"

inductive ButtonType where
  | button | submit | reset
deriving Repr, BEq, DecidableEq

def ButtonType.name : ButtonType → String
  | .button => "button"
  | .submit => "submit"
  | .reset => "reset"

/-- Safe, context-specific static attributes supported in the first view slice. -/
inductive StaticAttr where
  | className (value : String)
  | id (value : String)
  | ariaLabel (value : String)
  | buttonType (value : ButtonType)
deriving Repr, BEq

def StaticAttr.name : StaticAttr → String
  | .className _ => "class"
  | .id _ => "id"
  | .ariaLabel _ => "aria-label"
  | .buttonType _ => "type"

def StaticAttr.value : StaticAttr → String
  | .className value | .id value | .ariaLabel value => value
  | .buttonType value => value.name

inductive EventKind where
  | click
deriving Repr, BEq, DecidableEq

def EventKind.name : EventKind → String
  | .click => "click"

structure EventBinding where
  kind : EventKind
  eventName : String
  span : SourceSpan := .generated
deriving Repr, BEq

/- Explicit safe M4 view. Interpolation is text-only; raw HTML has no constructor. -/
mutual
  inductive View (Γ : Schema) where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (events : List EventBinding)
        (children : ViewChildren Γ) (span : SourceSpan := .generated)
    | text (value : String) (span : SourceSpan := .generated)
    | scalarText (name : String) (value : RxExpr Γ deps String)
        (span : SourceSpan := .generated)

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

def node (tag : HtmlTag) (children : List (View Γ))
    (attrs : List StaticAttr := []) (events : List EventBinding := [])
    (span : SourceSpan := .generated) : View Γ :=
  .element tag attrs events (.ofList children) span

end View

/- Static mount tree. Dynamic text positions are placeholders, never HTML. -/
mutual
  inductive MountNode where
    | element (tag : HtmlTag) (attrs : List StaticAttr) (children : MountChildren)
    | text (value : String)
    | dynamicText

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

structure ViewSplit (Γ : Schema) where
  template : MountNode
  textSinks : List (TextSink Γ)
  events : List MountedEvent

mutual
  private def View.mountNode : View Γ → MountNode
    | .element tag attrs _ children _ => .element tag attrs (children.mountChildren)
    | .text value _ => .text value
    | .scalarText _ _ _ => .dynamicText

  private def ViewChildren.mountChildren : ViewChildren Γ → MountChildren
    | .nil => .nil
    | .cons head tail => .cons head.mountNode tail.mountChildren
end

mutual
  private def View.textSinksAt (path : List Nat) : View Γ → List (TextSink Γ)
    | .element _ _ _ children _ => children.textSinksAt path 0
    | .text _ _ => []
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
    | .element _ _ bindings children _ =>
        bindings.map (fun binding => { path, binding }) ++ children.eventsAt path 0
    | .text _ _ | .scalarText _ _ _ => []

  private def ViewChildren.eventsAt (path : List Nat) (index : Nat) :
      ViewChildren Γ → List MountedEvent
    | .nil => []
    | .cons head tail =>
        head.eventsAt (path ++ [index]) ++ tail.eventsAt path (index + 1)
end

/-- Purely split a safe view into its mount tree, scalar sinks, and event bindings. -/
def View.split (value : View Γ) : ViewSplit Γ :=
  { template := value.mountNode
    textSinks := value.textSinksAt []
    events := value.eventsAt [] }

end LeanRx
