import LeanRx.Backend.JsAst

/-!
Compacts one flattened JavaScript module (ADR-0024): the hosts inlined by the
js-framework-benchmark build plus the compact-printed generated declarations.
The pass tokenizes the text, drops comments and every byte of whitespace that
no token pair needs, rewrites `x["name"]` to `x.name`, renames every top-level
binding and every binding declared inside a top-level function to a short
name, and fails closed on any construct it does not model (regular expression
literals, destructuring, multiple declarators, classes, labels, restricted
line breaks, a local that shadows a free or top-level name). With `prune`
(ADR-0031) it first drops every top-level function declaration and every
literal-initialized top-level `let`/`const`/`var` that no top-level statement
reaches through references. It is text-level and deliberately small; the
readable hosts in `runtime/` and the JavaScript AST printer remain the
contracts, and the benchmark gate syntax-checks and runs the result.
-/

namespace LeanRx.Js.Compact

inductive Kind where
  | word
  | number
  | string
  | template
  | punct
deriving Repr, BEq, DecidableEq, Inhabited

structure Token where
  kind : Kind
  text : String
  /-- A line break preceded the token (restricted-production check). -/
  newline : Bool := false
  /-- A template chunk that ends in `${` and opens an expression. -/
  opens : Bool := false
deriving Repr, BEq, Inhabited

inductive Role where
  | none
  | keyword
  | property
  | key
  | shorthand
  | reference
deriving Repr, BEq, DecidableEq, Inhabited

private def unsupported (message : String) : Error :=
  { code := "LRX-BE-031", message := s!"JavaScript compactor: {message}" }

private def keywords : List String := [
  "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default",
  "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "function",
  "if", "import", "in", "instanceof", "let", "new", "null", "of", "return", "static", "super",
  "switch", "this", "throw", "true", "try", "typeof", "undefined", "var", "void", "while",
  "with", "yield"]

private def punctuators : List String := [
  ">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=",
  "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=", "*=", "/=",
  "%=", "&=", "|=", "^=", "<<", ">>", "**",
  "{", "}", "(", ")", "[", "]", ";", ",", "<", ">", "+", "-", "*", "/", "%", "&", "|", "^",
  "!", "~", "?", ":", "=", "."]

private def isAsciiLetter (char : Char) : Bool :=
  ('a' ≤ char && char ≤ 'z') || ('A' ≤ char && char ≤ 'Z')

private def isAsciiDigit (char : Char) : Bool :=
  '0' ≤ char && char ≤ '9'

private def isIdentifierStart (char : Char) : Bool :=
  isAsciiLetter char || char == '_' || char == '$'

private def isIdentifierContinue (char : Char) : Bool :=
  isIdentifierStart char || isAsciiDigit char

private def identifierShaped (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest => isIdentifierStart first && rest.all isIdentifierContinue

private def charAt (chars : Array Char) (index : Nat) : Char :=
  chars.getD index '\x00'

private def startsWithAt (chars : Array Char) (index : Nat) (value : String) : Bool := Id.run do
  let mut offset := 0
  for char in value.toList do
    if charAt chars (index + offset) != char then return false
    offset := offset + 1
  return true

private def scanWhile (chars : Array Char) (start : Nat) (keep : Char → Bool) : Nat := Id.run do
  let mut index := start
  for _ in [start:chars.size] do
    if keep (charAt chars index) then index := index + 1 else break
  return index

/-- Index just past the closing quote of the string literal opened at `start`. -/
private def scanString (chars : Array Char) (start : Nat) (quote : Char) : Except Error Nat := do
  let mut index := start + 1
  for _ in [start:chars.size] do
    if index ≥ chars.size then break
    let char := charAt chars index
    if char == quote then return index + 1
    if char == '\n' then throw (unsupported "line break inside a string literal")
    index := index + (if char == '\\' then 2 else 1)
  throw (unsupported "unterminated string literal")

/-- Index just past a template chunk starting at `start` (a backtick or the `}`
closing an expression), and whether it ends in `${`. -/
private def scanTemplate (chars : Array Char) (start : Nat) : Except Error (Nat × Bool) := do
  let mut index := start + 1
  for _ in [start:chars.size] do
    if index ≥ chars.size then break
    let char := charAt chars index
    if char == '`' then return (index + 1, false)
    if char == '$' && charAt chars (index + 1) == '{' then return (index + 2, true)
    index := index + (if char == '\\' then 2 else 1)
  throw (unsupported "unterminated template literal")

private def isKeyword (token : Token) : Bool :=
  token.kind == .word && keywords.contains token.text

/-- The token can end a value, so a following `/` is division and a following
`[` is member access. -/
private def endsValue (token : Token) : Bool :=
  (token.kind == .word && !isKeyword token) ||
    (token.kind == .punct && (token.text == ")" || token.text == "]"))

def tokenize (source : String) : Except Error (Array Token) := do
  let chars := source.toList.toArray
  let size := chars.size
  let mut index := 0
  let mut newline := false
  let mut braces := 0
  let mut templates : List Nat := []
  let mut tokens : Array Token := #[]
  for _ in [0:size] do
    if index ≥ size then break
    let char := charAt chars index
    if char == '\n' then
      newline := true
      index := index + 1
    else if char == ' ' || char == '\t' || char == '\r' then
      index := index + 1
    else if char == '/' && charAt chars (index + 1) == '/' then
      index := scanWhile chars index (· != '\n')
    else if char == '/' && charAt chars (index + 1) == '*' then
      let mut close := index + 2
      for _ in [index:size] do
        if close + 1 ≥ size then throw (unsupported "unterminated comment")
        if charAt chars close == '*' && charAt chars (close + 1) == '/' then break
        close := close + 1
      index := close + 2
    else if isIdentifierStart char then
      let stop := scanWhile chars index isIdentifierContinue
      let text := String.ofList (chars.extract index stop).toList
      tokens := tokens.push { kind := .word, text, newline }
      newline := false
      index := stop
    else if isAsciiDigit char then
      let stop := scanWhile chars index fun c => isIdentifierContinue c || c == '.'
      let text := String.ofList (chars.extract index stop).toList
      tokens := tokens.push { kind := .number, text, newline }
      newline := false
      index := stop
    else if char == '"' || char == '\'' then
      let stop ← scanString chars index char
      let text := String.ofList (chars.extract index stop).toList
      tokens := tokens.push { kind := .string, text, newline }
      newline := false
      index := stop
    else if char == '`' || (char == '}' && templates.head? == some braces) then
      let (stop, opens) ← scanTemplate chars index
      if char == '}' then templates := templates.tail
      if opens then templates := braces :: templates
      let text := String.ofList (chars.extract index stop).toList
      tokens := tokens.push { kind := .template, text, newline, opens }
      newline := false
      index := stop
    else
      if char == '/' then
        match tokens.back? with
        | some previous =>
            unless endsValue previous || previous.kind == .number || previous.kind == .string do
              throw (unsupported "regular expression literal")
        | none => throw (unsupported "regular expression literal")
      match punctuators.find? (startsWithAt chars index ·) with
      | none => throw (unsupported s!"unexpected character {repr char}")
      | some text =>
          if text == "{" then braces := braces + 1
          if text == "}" then braces := braces - 1
          tokens := tokens.push { kind := .punct, text, newline }
          newline := false
          index := index + text.length
  unless templates.isEmpty do throw (unsupported "unterminated template expression")
  pure tokens

private def textAt (tokens : Array Token) (index : Nat) : String :=
  (tokens.getD index default).text

private def punctAt (tokens : Array Token) (index : Nat) (text : String) : Bool :=
  match tokens[index]? with
  | some token => token.kind == .punct && token.text == text
  | none => false

/-- Bracket depth change contributed by a token. -/
private def depthDelta (token : Token) : Int :=
  match token.kind with
  | .punct =>
      if token.text == "{" || token.text == "(" || token.text == "[" then 1
      else if token.text == "}" || token.text == ")" || token.text == "]" then -1
      else 0
  | .template => (if token.text.startsWith "}" then -1 else 0) + (if token.opens then 1 else 0)
  | _ => 0

private def opensObject (tokens : Array Token) (index : Nat) : Bool :=
  if index == 0 then false else
  let previous := tokens.getD (index - 1) default
  (previous.kind == .punct && ["(", ",", "=", ":", "?", "["].contains previous.text) ||
    (previous.kind == .word && previous.text == "return")

/-- Classifies every word token as a keyword, a property (after `.`/`?.`, an
object key, or a method name), an object shorthand member, or a reference. -/
def analyze (tokens : Array Token) : Except Error (Array Role) := do
  let mut stack : List (String × Bool) := []
  let mut roles : Array Role := #[]
  for index in [0:tokens.size] do
    let token := tokens.getD index default
    let mut role := Role.none
    match token.kind with
    | .punct =>
        if token.text == "{" then stack := ("{", opensObject tokens index) :: stack
        else if token.text == "(" || token.text == "[" then stack := (token.text, false) :: stack
        else if token.text == "}" || token.text == ")" || token.text == "]" then
          let expected := if token.text == "}" then "{" else if token.text == ")" then "(" else "["
          match stack with
          | (opener, _) :: rest =>
              unless opener == expected do throw (unsupported "unbalanced brackets")
              stack := rest
          | [] => throw (unsupported "unbalanced brackets")
    | .template =>
        if token.text.startsWith "}" then
          match stack with
          | ("${", _) :: rest => stack := rest
          | _ => throw (unsupported "unbalanced template expression")
        if token.opens then stack := ("${", false) :: stack
    | .word =>
        let previous := if index == 0 then "" else textAt tokens (index - 1)
        let previousPunct := index > 0 && (tokens.getD (index - 1) default).kind == .punct
        let next := textAt tokens (index + 1)
        let nextPunct := (tokens.getD (index + 1) default).kind == .punct
        if previousPunct && (previous == "." || previous == "?.") then role := .property
        else if isKeyword token then role := .keyword
        else
          match stack with
          | ("{", true) :: _ =>
              if previousPunct && (previous == "{" || previous == ",") then
                if nextPunct && (next == ":" || next == "(") then role := .key
                else if nextPunct && (next == "," || next == "}") then role := .shorthand
                else throw (unsupported "object literal member")
              else role := .reference
          | _ => role := .reference
    | _ => pure ()
    roles := roles.push role
  unless stack.isEmpty do throw (unsupported "unbalanced brackets")
  pure roles

/-- Index of the `,`/closing bracket at depth 0 that ends a default value. -/
private def skipDefault (tokens : Array Token) (start stop : Nat) : Nat := Id.run do
  let mut depth : Int := 0
  for index in [start:stop] do
    let token := tokens.getD index default
    if token.kind == .punct then
      if token.text == "(" || token.text == "[" || token.text == "{" then depth := depth + 1
      else if token.text == ")" || token.text == "]" || token.text == "}" then
        if depth == 0 then return index
        depth := depth - 1
      else if token.text == "," && depth == 0 then return index
  return stop

private def bindable (tokens : Array Token) (roles : Array Role) (index : Nat) :
    Except Error String := do
  let role := roles.getD index .none
  unless role == .reference || role == .shorthand do
    throw (unsupported s!"binding '{textAt tokens index}' is not a plain identifier")
  pure (textAt tokens index)

/-- Parameter names of the list opened by the `(` at `paren`, and the index of
its `)`. -/
private def parameters (tokens : Array Token) (roles : Array Role) (paren stop : Nat) :
    Except Error (List String × Nat) := do
  let mut names : List String := []
  let mut index := paren + 1
  for _ in [paren:stop] do
    if index ≥ stop then break
    if punctAt tokens index ")" then return (names, index)
    unless (tokens.getD index default).kind == .word do
      throw (unsupported s!"parameter '{textAt tokens index}'")
    names := names ++ [← bindable tokens roles index]
    index := index + 1
    if punctAt tokens index "=" then index := skipDefault tokens (index + 1) stop
    if punctAt tokens index "," then index := index + 1
  throw (unsupported "unterminated parameter list")

/-- Every name bound inside a top-level function: its parameters (when `lo`
points at its `(`), nested function names and parameters, `const`/`let`/`var`
declarations, `catch` bindings, object-literal method parameters, and arrow
function parameters. -/
private def bindings (tokens : Array Token) (roles : Array Role) (lo stop : Nat) :
    Except Error (List String) := do
  let mut names : List String := []
  let mut index := lo
  for _ in [lo:stop] do
    if index ≥ stop then break
    let token := tokens.getD index default
    if index == lo && punctAt tokens index "(" then
      let (params, close) ← parameters tokens roles index stop
      names := names ++ params
      index := close + 1
    else if token.kind != .word then
      index := index + 1
    else if roles.getD index .none == .key && punctAt tokens (index + 1) "(" then
      let (params, close) ← parameters tokens roles (index + 1) stop
      names := names ++ params
      index := close + 1
    else if token.text == "function" then
      let mut paren := index + 1
      if (tokens.getD paren default).kind == .word then
        names := names ++ [← bindable tokens roles paren]
        paren := paren + 1
      unless punctAt tokens paren "(" do throw (unsupported "function without a parameter list")
      let (params, close) ← parameters tokens roles paren stop
      names := names ++ params
      index := close + 1
    else if token.text == "const" || token.text == "let" || token.text == "var" then
      unless (tokens.getD (index + 1) default).kind == .word do
        throw (unsupported "destructuring declaration")
      names := names ++ [← bindable tokens roles (index + 1)]
      let mut depth : Int := 0
      for scan in [index + 2:stop] do
        let current := tokens.getD scan default
        let delta := depthDelta current
        if current.kind == .punct && depth == 0 &&
            [";", ")", "]", "}"].contains current.text then
          break
        if current.kind == .punct && depth == 0 && current.text == "," then
          throw (unsupported "multiple declarators in one declaration")
        if current.kind == .word && depth == 0 &&
            (current.text == "of" || current.text == "in") then
          break
        depth := depth + delta
      index := index + 2
    else if token.text == "catch" then
      if punctAt tokens (index + 1) "(" then
        names := names ++ [← bindable tokens roles (index + 2)]
      index := index + 1
    else
      index := index + 1
  for arrow in [lo:stop] do
    unless punctAt tokens arrow "=>" do continue
    if arrow == 0 then throw (unsupported "arrow function without parameters")
    let previous := tokens.getD (arrow - 1) default
    if previous.kind == .word then
      names := names ++ [← bindable tokens roles (arrow - 1)]
    else if previous.kind == .punct && previous.text == ")" then
      let mut depth : Int := 0
      let mut paren := arrow - 1
      for back in [0:arrow] do
        let position := arrow - 1 - back
        let current := tokens.getD position default
        if current.kind == .punct then
          if [")", "]", "}"].contains current.text then depth := depth + 1
          else if current.text == "(" || current.text == "[" || current.text == "{" then
            depth := depth - 1
            if depth == 0 then
              paren := position
              break
      let (params, _) ← parameters tokens roles paren stop
      names := names ++ params
    else
      throw (unsupported "arrow function parameter list")
  pure names.eraseDups

private def poolFirst (upper : Bool) : Array Char :=
  (if upper then "ABCDEFGHIJKLMNOPQRSTUVWXYZ" else "abcdefghijklmnopqrstuvwxyz").toList.toArray

private def poolRest : Array Char :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$".toList.toArray

/-- The `n`-th short name: one letter, then a letter followed by one or two
pool characters. Top-level names start with an uppercase letter and local
names with a lowercase letter, so the two pools never collide. -/
def poolName (upper : Bool) (n : Nat) : String :=
  let first := poolFirst upper
  if n < 26 then String.ofList [first.getD n 'x']
  else if n - 26 < 26 * 64 then
    let m := n - 26
    String.ofList [first.getD (m / 64) 'x', poolRest.getD (m % 64) 'x']
  else
    let k := n - 26 - 26 * 64
    String.ofList
      [first.getD (k / 4096) 'x', poolRest.getD ((k / 64) % 64) 'x', poolRest.getD (k % 64) 'x']

private structure Candidate where
  name : String
  count : Nat
  first : Nat

/-- Assigns short names by descending use count (ties by first occurrence),
skipping reserved words and the names in `avoid`. -/
private def assign (candidates : Array Candidate) (avoid : List String) (upper : Bool) :
    List (String × String) := Id.run do
  let sorted := candidates.qsort fun a b =>
    a.count > b.count || (a.count == b.count && a.first < b.first)
  let mut next := 0
  let mut map : List (String × String) := []
  for candidate in sorted do
    let mut chosen := poolName upper next
    next := next + 1
    for _ in [0:256] do
      if keywords.contains chosen || !Ident.valid chosen || avoid.contains chosen then
        chosen := poolName upper next
        next := next + 1
      else break
    map := map ++ [(candidate.name, chosen)]
  return map

private def countUses (tokens : Array Token) (roles : Array Role) (lo stop : Nat)
    (names : List String) : Array Candidate := Id.run do
  let mut candidates : Array Candidate := #[]
  for index in [lo:stop] do
    let role := roles.getD index .none
    unless role == .reference || role == .shorthand do continue
    let name := textAt tokens index
    unless names.contains name do continue
    match candidates.findIdx? (·.name == name) with
    | some position =>
        candidates := candidates.modify position fun c => { c with count := c.count + 1 }
    | none => candidates := candidates.push { name, count := 1, first := index }
  return candidates

private def lookupName (map : List (String × String)) (name : String) : Option String :=
  (map.find? (·.1 == name)).map (·.2)

private def needsSpace (previous current : Token) : Bool :=
  let wordy := fun (token : Token) => token.kind == .word || token.kind == .number
  (wordy previous && wordy current) ||
    (previous.text.endsWith "+" && current.text.startsWith "+") ||
    (previous.text.endsWith "-" && current.text.startsWith "-")

/-- A token that is a single literal value: a number, a string, a template
without expressions, or `null`/`undefined`/`true`/`false`. -/
private def literalToken (token : Token) : Bool :=
  token.kind == .number || token.kind == .string ||
    (token.kind == .template && !token.opens && token.text.endsWith "`") ||
    (token.kind == .word && ["null", "undefined", "true", "false"].contains token.text)

/-- The name a top-level segment declares when dropping the segment cannot
change the behaviour of the code that remains: a function declaration, or a
`let`/`const`/`var` whose initializer is absent or a single literal. Any other
segment (a statement, or a declaration whose initializer may have effects) is
a root that stays. -/
private def prunableName (tokens : Array Token) (lo stop : Nat) : Option String :=
  let head := tokens.getD lo default
  let name := tokens.getD (lo + 1) default
  if head.kind != .word || name.kind != .word then none
  else if head.text == "function" then some name.text
  else if head.text == "let" || head.text == "const" || head.text == "var" then
    if punctAt tokens (lo + 2) ";" && lo + 3 == stop then some name.text
    else if punctAt tokens (lo + 2) "=" && literalToken (tokens.getD (lo + 3) default) &&
        punctAt tokens (lo + 4) ";" && lo + 5 == stop then some name.text
    else none
  else none

/-- The top-level segments that stay after pruning: every root (a segment that
declares nothing prunable) and, transitively, every prunable declaration that
a kept segment references outside its own local bindings. -/
private def reachable (tokens : Array Token) (roles : Array Role)
    (segments : Array (Nat × Nat)) (locals : Array (List String)) : Array Bool := Id.run do
  let declared := segments.map fun (lo, stop) => prunableName tokens lo stop
  let mut live := declared.map (·.isNone)
  let mut changed := true
  for _ in [0:segments.size + 1] do
    unless changed do break
    changed := false
    for segment in [0:segments.size] do
      unless live.getD segment false do continue
      let (lo, stop) := segments.getD segment (0, 0)
      let names := locals.getD segment []
      for index in [lo:stop] do
        let role := roles.getD index .none
        unless role == .reference || role == .shorthand do continue
        let name := textAt tokens index
        if names.contains name then continue
        for target in [0:segments.size] do
          if !(live.getD target false) && declared.getD target none == some name then
            live := live.set! target true
            changed := true
  return live

/-- Compacts a flattened module: see the module docstring. With `prune`, the
top-level declarations no top-level statement reaches are dropped first. -/
def compact (source : String) (prune : Bool := false) : Except Error String := do
  let tokens ← tokenize source
  let roles ← analyze tokens
  for index in [0:tokens.size] do
    let token := tokens.getD index default
    let role := roles.getD index .none
    if token.kind == .word && role != .property && role != .key &&
        ["class", "with", "yield", "await", "import", "export", "debugger", "switch",
          "case", "default", "do", "void", "delete", "eval", "arguments"].contains token.text then
      throw (unsupported s!"keyword '{token.text}'")
    if index == 0 then continue
    let previous := tokens.getD (index - 1) default
    if token.newline && previous.kind == .word &&
        ["return", "throw", "break", "continue"].contains previous.text then
      throw (unsupported s!"line break after '{previous.text}'")
    if token.newline && token.kind == .punct && (token.text == "++" || token.text == "--") then
      throw (unsupported s!"line break before '{token.text}'")
  -- Top-level segments end at a depth-0 `}` or `;`.
  let mut segments : Array (Nat × Nat) := #[]
  let mut topNames : List String := []
  let mut depth : Int := 0
  let mut start := 0
  for index in [0:tokens.size] do
    let token := tokens.getD index default
    if depth == 0 && token.kind == .word then
      if token.text == "function" || token.text == "let" || token.text == "const" ||
          token.text == "var" then
        if (tokens.getD (index + 1) default).kind == .word then
          topNames := topNames ++ [← bindable tokens roles (index + 1)]
    depth := depth + depthDelta token
    if depth < 0 then throw (unsupported "unbalanced brackets")
    if depth == 0 && token.kind == .punct && (token.text == "}" || token.text == ";") then
      segments := segments.push (start, index + 1)
      start := index + 1
  unless start == tokens.size do throw (unsupported "trailing tokens")
  let uniqueTop := topNames.eraseDups
  let mut locals : Array (List String) := #[]
  for (lo, stop) in segments do
    if textAt tokens lo == "function" && (tokens.getD (lo + 1) default).kind == .word then
      locals := locals.push (← bindings tokens roles (lo + 2) stop)
    else
      locals := locals.push []
  let live := if prune then reachable tokens roles segments locals
    else segments.map fun _ => true
  let mut free : List String := []
  let mut topCandidates : Array Candidate := #[]
  for segment in [0:segments.size] do
    unless live.getD segment false do continue
    let (lo, stop) := segments.getD segment (0, 0)
    let names := locals.getD segment []
    for index in [lo:stop] do
      let role := roles.getD index .none
      unless role == .reference || role == .shorthand do continue
      let name := textAt tokens index
      if names.contains name then
        if uniqueTop.contains name then
          throw (unsupported s!"local '{name}' shadows a top-level binding")
      else if uniqueTop.contains name then
        match topCandidates.findIdx? (·.name == name) with
        | some position =>
            topCandidates := topCandidates.modify position fun c => { c with count := c.count + 1 }
        | none => topCandidates := topCandidates.push { name, count := 1, first := index }
      else if !free.contains name then
        free := free ++ [name]
  for segment in [0:segments.size] do
    unless live.getD segment false do continue
    for name in locals.getD segment [] do
      if free.contains name then
        throw (unsupported s!"local '{name}' shadows a free identifier")
  for name in uniqueTop do
    unless topCandidates.any (·.name == name) do
      topCandidates := topCandidates.push { name, count := 0, first := tokens.size }
  let topMap := assign topCandidates free true
  let mut output : Array Token := #[]
  for segment in [0:segments.size] do
    unless live.getD segment false do continue
    let (lo, stop) := segments.getD segment (0, 0)
    let names := locals.getD segment []
    let localMap := assign (countUses tokens roles lo stop names) free false
    let mut index := lo
    for _ in [lo:stop] do
      if index ≥ stop then break
      let token := tokens.getD index default
      let role := roles.getD index .none
      if token.kind == .punct && token.text == "[" && index > 0 &&
          endsValue (tokens.getD (index - 1) default) &&
          (tokens.getD (index + 1) default).kind == .string && punctAt tokens (index + 2) "]" then
        let literal := textAt tokens (index + 1)
        let inner := String.ofList (literal.toList.drop 1).dropLast
        if identifierShaped inner then
          output := output.push { kind := .punct, text := "." }
          output := output.push { kind := .word, text := inner }
          index := index + 3
          continue
      if token.kind == .word && (role == .reference || role == .shorthand) then
        let renamed := match lookupName localMap token.text with
          | some short => some short
          | none => lookupName topMap token.text
        match renamed with
        | some short =>
            let text := if role == .shorthand then token.text ++ ":" ++ short else short
            output := output.push { kind := .word, text }
        | none => output := output.push { token with newline := false }
      else
        output := output.push { token with newline := false }
      index := index + 1
  let mut rendered := ""
  let mut previous : Option Token := none
  for token in output do
    if let some last := previous then
      if needsSpace last token then rendered := rendered ++ " "
    rendered := rendered ++ token.text
    previous := some token
  pure rendered

end LeanRx.Js.Compact
