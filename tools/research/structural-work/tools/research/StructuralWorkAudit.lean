import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Persistence.Store

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def safeEdge (left right : Value) : IO UnionEdge := do
  if same : Value.sameExactFootprint left right then
    pure ⟨left,right,.workspace (.text "structural-fixture"),Value.sameExactFootprint_sound same⟩
  else throw (IO.userError "fixture Union changes Exact footprint")

private def makeDB (path : System.FilePath) (values : List Value) (edges : List UnionEdge) : IO Unit := do
  check (!(← path.pathExists)) "preserve fixture"
  let snapshot ← DB.PageMap.create path (Persistence.valueToJson (.text "structural-fixture")).compress
  let _ ← DB.PageMap.withWriter snapshot fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    addUnions intern edges
    writeChange writer ⟨ids,[],!edges.isEmpty⟩
  pure ()

private def parent (work : Value) : IO AllEdge := do
  let root := Value.text "the owning investigation"
  if distinct : root ≠ work then
    pure (AllEdge.make root [work] (by simp) (by simpa using distinct))
  else throw (IO.userError "invalid parent")

private def checkedRequest (raw : Handoff) (workspace : System.FilePath)
    (targets : Option (List String) := some ["source.txt"]) : IO Handoff := do
  raw.checkSources {workspace, deadline := (← IO.monoMsNow)+30000, native := true, targets}

private def selection (paths : List System.FilePath) : Config.Selection := {
  label := "structural"
  read := paths.map fun path => {name := path.fileName.getD "fixture",path}
  write := none
  handoffChars := 24000
  -- A successful certified root must not start this provider.
  semanticMatcher := some ["/does-not-exist/structural-provider-must-not-run"]}

private def ask (paths : List System.FilePath) (work : String) (receipt : String) : IO Handoff := do
  let snapshots ← paths.mapM fun path => do pure (some (← DB.PageMap.pin path))
  let some raw ← computeAutomaticHandoff (selection paths) snapshots work [] true none [] true
      (receipt := some receipt) |
    throw (IO.userError "no structural result")
  check (raw.reason.contains "producer=work-class" && raw.completed > 0 && raw.blocksCurrent)
    s!"not the structural route: {raw.reason}"
  let some reference := raw.equalitySelection | throw (IO.userError "missing equality receipt")
  let inspected ← SelectionAudit.inspect reference
  check (inspected.compress.contains "\"classIdentity\":true") "class admission was not replayed"
  return raw

private def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve prior test"
  FileSystem.privateDirectory output
  let workspace := output / "workspace"
  FileSystem.privateDirectory workspace
  let body := "SOURCE_ORIGINAL_MARKER\nsecond line\n"
  IO.FS.writeFile (workspace / "source.txt") body
  let input := Json.mkObj [("command",toJson "cat source.txt")]
  let aliasInput := Json.mkObj [("command",toJson "sed -n '1,2p' source.txt")]
  let tool : ToolEvent := {
    name := "Bash"
    useId := "original-read"
    input := input.compress
    response := (toJson body).compress}
  let aliasTool := {tool with input := aliasInput.compress, useId := "alias-read"}
  let work := canonicalToolWork tool
  let aliasWork := canonicalToolWork aliasTool
  let capture ← SourceEvidence.capture workspace input ((← IO.monoMsNow)+5000)
  check (capture.record.valid && capture.record.closed) "source capture did not close"
  let result := Value.text tool.response
  let occurrence := Value.applyList .occurrence [.semantic result,.semantic (.text work)]
  let original := OutcomeEdge.make (.text work) result [occurrence] (by simp) (by simp [maxOutcomeObservations])
  let all ← parent original.work
  let certificate := SourceEvidence.receipt (.text "fixture-chat") (.text "fixture-turn")
    (.text tool.useId) original.relation capture.record
  -- The two Work atoms are connected only by congruence, not an explicit
  -- text-to-text Union. These are trusted fixture generators.
  let a := Value.text "identity-left"
  let b := Value.text "identity-right"
  let fa := Value.applyList .inquiry [.semantic a]
  let fb := Value.applyList .inquiry [.semantic b]
  let edges ← [safeEdge a b,safeEdge fa original.work,safeEdge fb (.text aliasWork)].mapM id
  let database := output / "one.egg"
  makeDB database [original.relation,all.relation,certificate] edges
  let originalHead := (← DB.PageMap.pin database).head
  let literalReceipt ← Receipt.fresh
  let literal ← ask [database] work literalReceipt
  let literal ← checkedRequest literal workspace
  check (literal.completed > 0 && literal.blocksCurrent && literal.text.contains "SOURCE_ORIGINAL_MARKER")
    "literal reuse lost source authority or body"
  let aliasReceipt ← Receipt.fresh
  let aliased ← ask [database] aliasWork aliasReceipt
  let aliasedChecked ← checkedRequest aliased workspace
  check (aliasedChecked.completed > 0 && aliasedChecked.blocksCurrent &&
      aliasedChecked.coveredFragments.contains aliasWork) "congruence alias did not control its actual Work"
  let some aliasReference := aliased.equalitySelection | throw (IO.userError "missing alias reference")
  let inspected ← SelectionAudit.inspect aliasReference
  check (inspected.compress.contains "congruence") "congruence was misclassified as direct equality"
  let deliveredPublic ← automaticHandoff (selection [database]) aliasWork [] true none [] true true
    (some {workspace,deadline := (← IO.monoMsNow)+30000,native := true,targets := some ["source.txt"]})
    (publishMemo := false)
  check (deliveredPublic.any fun handoff => handoff.blocksCurrent && handoff.text.contains "SOURCE_ORIGINAL_MARKER")
    "public automaticHandoff did not use the certified path"
  let wrongTarget ← checkedRequest aliased workspace (some ["other.txt"])
  check (!wrongTarget.blocksCurrent && wrongTarget.completed == 0) "uncovered target acquired control"
  IO.FS.writeFile (workspace / "source.txt") "CHANGED_CONTENT\n"
  let stale ← checkedRequest aliased workspace
  check (!stale.blocksCurrent && stale.completed == 0 && stale.text.contains "SOURCE_ORIGINAL_MARKER")
    "changed file retained authority or erased historical body"
  IO.FS.writeFile (workspace / "source.txt") body
  let unknownDB := output / "unknown.egg"
  makeDB unknownDB [original.relation,all.relation] []
  let unknown ← ask [unknownDB] work (← Receipt.fresh)
  let unknown ← checkedRequest unknown workspace
  check (!unknown.blocksCurrent && unknown.completed == 0) "unverified observation controlled Work"
  let unknownSnapshot ← DB.PageMap.pin unknownDB
  check ((← indexedIdentifiedRoot (selection [unknownDB]) [some unknownSnapshot] aliasWork []).isNone)
    "missing equality became a terminal result"
  let parentDB := output / "parent.egg"
  makeDB parentDB [original.relation,certificate] edges
  let parentSnapshot ← DB.PageMap.pin parentDB
  check ((← indexedIdentifiedRoot (selection [parentDB]) [some parentSnapshot] aliasWork []).isNone)
    "parent-only owner was certified as a child"
  let childDB := output / "child.egg"
  makeDB childDB [all.relation] []
  let cross ← ask [parentDB,childDB] aliasWork (← Receipt.fresh)
  let cross ← checkedRequest cross workspace
  check (cross.blocksCurrent && cross.completed > 0 && cross.text.contains "SOURCE_ORIGINAL_MARKER")
    "cross-DB original ownership and child membership did not join"
  let mcpWork := "mcp__issues__get\n{\"id\":42}"
  let mcp := OutcomeEdge.make (.text mcpWork) (.text "EXTERNAL_OBSERVATION") [] (by simp) (by simp)
  let mcpAll ← parent mcp.work
  let mcpDB := output / "mcp.egg"
  makeDB mcpDB [mcp.relation,mcpAll.relation] []
  let external ← ask [mcpDB] mcpWork (← Receipt.fresh)
  let external ← checkedRequest external workspace none
  check (!external.blocksCurrent && external.completed == 0) "MCP acquired unchecked completion"
  check ((← DB.PageMap.pin database).head == originalHead) "read-only query changed source publication"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("literal",toJson literal),("congruenceAlias",toJson aliasedChecked),
    ("aliasInspection",inspected),("crossDB",toJson cross),
    ("wrongTarget",toJson wrongTarget),("stale",toJson stale),
    ("unknown",toJson unknown),("external",toJson external),
    ("noEqualityRejected",toJson true),("parentOnlyRejected",toJson true),
    ("originalHeadUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).pretty

def main (args : List String) : IO Unit := do
  match args with
  | ["small",output] => run (.mk output)
  | _ => throw (IO.userError "StructuralWorkAudit small NEW-OUTPUT")
