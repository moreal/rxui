import LeanRx.Backend.JsCompact

namespace LeanRxTest.Backend.JsCompact

open LeanRx.Js

private def compact (source : String) (prune : Bool := false) : IO String :=
  match Compact.compact source prune with
  | .ok output => pure output
  | .error error =>
      throw <| IO.userError s!"compactor rejected fixture: {error.code}: {error.message}"

private def expectRejected (label source : String) : IO Unit :=
  match Compact.compact source with
  | .ok output => throw <| IO.userError s!"compactor accepted {label}: {output}"
  | .error error =>
      unless error.code == "LRX-BE-031" do
        throw <| IO.userError s!"compactor returned the wrong diagnostic for {label}: {error.code}"

-- A host-shaped fixture: comments, a top-level `let`, template literals,
-- default parameters, object literal methods, shorthand members, arrow
-- functions, `catch` bindings, optional chaining, and the generated module's
-- bracketed member access.
private def fixture : String :=
  "// leading comment\n" ++
  "function createElement(tag) {\n" ++
  "  return document.createElement(tag); // trailing comment\n" ++
  "}\n" ++
  "let nextIdValue = 0;\n" ++
  "function uniqueId(prefix) {\n" ++
  "  nextIdValue += 1;\n" ++
  "  return `${prefix}-${nextIdValue}`;\n" ++
  "}\n" ++
  "function region(parent, rootItem = null) {\n" ++
  "  const entries = new Map(); /* block\n comment */\n" ++
  "  let stamp = 0;\n" ++
  "  return {\n" ++
  "    update(items, context) {\n" ++
  "      for (let index = 0; index < items.length; index += 1) {\n" ++
  "        const key = items[index][0];\n" ++
  "        const entry = { key, handle: null, stamp, pos: -1 };\n" ++
  "        entries.set(key, entry);\n" ++
  "        if (entry.stamp === stamp) throw new Error(`dup ${String(key)}`);\n" ++
  "      }\n" ++
  "      return items.map((item) => item.pos - -context) ?? [];\n" ++
  "    },\n" ++
  "    dispose() {\n" ++
  "      try { parent.remove(); } catch (error) { stamp = typeof error; }\n" ++
  "      return rootItem?.slice() ?? [];\n" ++
  "    },\n" ++
  "  };\n" ++
  "}\n" ++
  "function run(state){const rows=state[\"rows\"];return (Math[\"round\"]" ++
    "((Math[\"random\"]()*1000))%rows[\"length\"])+rows[\"not-an-identifier\"];}\n" ++
  "globalThis.leanrxDispose=run(document[\"body\"]);\n"

private def expected : String :=
  "function C(a){return document.createElement(a);}let A=0;function D(a){A+=1;" ++
  "return`${a}-${A}`;}function E(f,g=null){const h=new Map();let a=0;return{update(b,i){" ++
  "for(let c=0;c<b.length;c+=1){const d=b[c][0];const e={key:d,handle:null,stamp:a,pos:-1};" ++
  "h.set(d,e);if(e.stamp===a)throw new Error(`dup ${String(d)}`);}" ++
  "return b.map((j)=>j.pos- -i)??[];},dispose(){try{f.remove();}catch(k){a=typeof k;}" ++
  "return g?.slice()??[];},};}function B(b){const a=b.rows;" ++
  "return(Math.round((Math.random()*1000))%a.length)+a[\"not-an-identifier\"];}" ++
  "globalThis.leanrxDispose=B(document.body);"

def run : IO Unit := do
  let output ← compact fixture
  unless output == expected do
    throw <| IO.userError s!"JavaScript compactor golden changed:\n{output}"
  let repeated ← compact fixture
  unless repeated == output do
    throw <| IO.userError "JavaScript compactor bytes were not deterministic"
  -- Locals are named by descending use count; top-level names by use count
  -- then declaration order, both skipping reserved words and free names.
  unless Compact.poolName false 0 == "a" && Compact.poolName false 25 == "z" &&
      Compact.poolName false 26 == "aa" && Compact.poolName true 0 == "A" &&
      Compact.poolName true 27 == "Ab" && Compact.poolName false (26 + 26 * 64) == "aaa" do
    throw <| IO.userError "JavaScript compactor name pool changed"
  let shadowed ← compact
    "function first(document) { return document; }\nfunction second() { return 1; }"
  unless shadowed == "function A(a){return a;}function B(){return 1;}" do
    throw <| IO.userError s!"JavaScript compactor renamed a parameter wrongly: {shadowed}"
  -- A name that is free anywhere in the module is never reused for a local.
  let free ← compact "function first(value) { return value + a; }"
  unless free == "function A(b){return b+a;}" do
    throw <| IO.userError s!"JavaScript compactor reused a free name: {free}"
  -- ADR-0031: with `prune`, only the declarations the top-level statements
  -- reach are kept: the fixture's mount statement reaches `run` alone, so
  -- `createElement`, `uniqueId` with its counter, and `region` are dropped and
  -- the remaining name pool is renumbered.
  let pruned ← compact fixture (prune := true)
  unless pruned == "function A(b){const a=b.rows;return(Math.round((Math.random()*1000))" ++
      "%a.length)+a[\"not-an-identifier\"];}globalThis.leanrxDispose=A(document.body);" do
    throw <| IO.userError s!"JavaScript compactor pruned wrongly:\n{pruned}"
  -- A declaration whose initializer may have effects is a root; reachability
  -- is transitive and a self-reference does not keep a declaration alive.
  let transitive ← compact
    ("let counter = 0;\nfunction bump() { counter += 1; return counter; }\n" ++
      "function unused() { return bump(); }\nconst kept = bump();\n" ++
      "function dead(x) { return dead(x); }\n") (prune := true)
  unless transitive == "let A=0;function B(){A+=1;return A;}const C=B();" do
    throw <| IO.userError s!"JavaScript compactor pruned the wrong declarations:\n{transitive}"
  -- Without a statement nothing is reachable; a module that is only
  -- declarations is kept whole unless pruning is requested.
  let whole ← compact "function f() { return 1; }"
  unless whole == "function A(){return 1;}" do
    throw <| IO.userError s!"JavaScript compactor changed without prune: {whole}"
  let emptied ← compact "function f() { return 1; }" (prune := true)
  unless emptied == "" do
    throw <| IO.userError s!"JavaScript compactor kept an unreachable declaration: {emptied}"
  expectRejected "a regular expression literal" "function f(a) { return /x/.test(a); }"
  expectRejected "a destructuring declaration" "function f(a) { const [b] = a; return b; }"
  expectRejected "multiple declarators" "function f(a) { let b = 1, c = 2; return a; }"
  expectRejected "a class" "class A {}"
  expectRejected "a line break after return" "function f(a) {\n  return\n  a;\n}"
  expectRejected "a line break before ++" "function f(a) {\n  a\n  ++a;\n}"
  expectRejected "a local shadowing a free name"
    "function f(document) { return document; }\nfunction g() { return document; }"
  expectRejected "a local shadowing a top-level name"
    "function f(g) { return g; }\nfunction g() { return 1; }"
  expectRejected "an export" "export function f(a) { return a; }"
  expectRejected "unbalanced brackets" "function f(a) { return a; "
  expectRejected "an unterminated string" "function f(a) { return \"a; }"

end LeanRxTest.Backend.JsCompact
