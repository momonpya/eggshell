import Main
import Eggshell.ContractAudit
import tools.research.ProjectIngressAudit
import tools.research.ReplayWorkChecks
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction
namespace Eggshell.Research.MetadataIngressChecks
#print axioms Journal.description_content_exact
#print axioms Journal.description_name_exact
#print axioms Journal.description_turn_exact
#print axioms Journal.finish_projection_identical
#print axioms Journal.described_step_exact
#print axioms Journal.described_projection_exact
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path (value.pretty++"\n")
private def rejects (action : IO α) : IO Bool := do
  try discard <| action; return false catch _ => return true
private def literalStep (old : Journal.Frontier) (ordinal : Nat) (value : Journal.Entry) : Journal.Frontier := Id.run do
  let raw := (toJson value).compress.toUTF8
  let ordered := old.maximum.all (·.before value.clock)
  let count := old.count+1
  let floor := if ordered then old.floor else count
  let maximum := match old.maximum with
    | none => value.clock
    | some previous => if previous.before value.clock then value.clock else previous
  let bytes := old.bytes+raw.size
  return {
    producer := Journal.implementation,count,latest := ordinal+1,floor,maximum := some maximum,bytes
    chain := Index.contentKey (old.chain,ordinal,Sha256.hex raw,count,floor,maximum,bytes)}
private def prepare (root : System.FilePath) : IO Unit := do
  check (!(← (root/"inputs.json").pathExists)) "preserve frozen ingress inputs"
  let fixture ← read (root/"frozen.json")
  let rows ← IO.ofExcept (fromJson? fixture : Except String (Array Json))
  let mut inputs := #[]
  for row in rows do
    let raw ← IO.ofExcept (row.getObjValAs? String "directory")
    let source ← DB.PageMap.pin (.mk raw)
    let mut targets : Array (String × DB.PageMap.Head) := #[]
    for slot in [:16] do
      let target ← Persistence.ensureSnapshot (source.directory.parent.get!/"targets"/toString slot)
      targets := targets.push (target.directory.toString,target.head)
    let seed ← IO.ofExcept (row.getObjValAs? (Array Journal.Entry) "seed")
    let analysis ← IO.ofExcept (row.getObjValAs? (Array Journal.Entry) "analysis")
    let values := (seed++analysis).map fun value =>
      let augment := fun (known : Journal.Knowledge) => {known with
        related := targets.map (fun (_,head) => ⟨head,none⟩)}
      let payload := match value.payload with
        | .start occurrence work query known => .start occurrence work query (augment known)
        | .answer occurrence query text known => .answer occurrence query text (augment known)
        | other => other
      {value with payload}
    inputs := inputs.push (row.setObjVal! "targets" (toJson targets)
      |>.setObjVal! "values" (toJson values))
  save (root/"inputs.json") (toJson inputs)
private def observe (root : System.FilePath) : IO Unit := do
  let inputs ← IO.ofExcept (fromJson? (← read (root/"inputs.json")) : Except String (Array Json))
  let mut reports := #[]
  for row in inputs do
    let raw ← IO.ofExcept (row.getObjValAs? String "directory")
    let head ← IO.ofExcept (row.getObjValAs? DB.PageMap.Head "head")
    let source ← DB.PageMap.pin (.mk raw)
    check (source.head == head) "frozen source changed"
    let values ← IO.ofExcept (row.getObjValAs? (Array Journal.Entry) "values")
    let targets ← IO.ofExcept (row.getObjValAs? (Array (String × DB.PageMap.Head)) "targets")
    let began ← IO.monoMsNow
    for value in values do discard <| Journal.append source value
    let appendMs := (← IO.monoMsNow)-began
    let owner := DB.Sidecar.Owner.ofSnapshot source
    let mut observations := #[]
    for (path,expected) in targets do
      let target ← DB.PageMap.pin (.mk path)
      check (target.head == expected) "frozen target changed"
      let began ← IO.monoMsNow
      let imported ← Journal.importFeed target owner ((← IO.monoMsNow)+30000)
      let elapsed := (← IO.monoMsNow)-began
      check (imported.complete && imported.added == values.size) "metadata slice lost an original"
      let some journal ← Journal.open? target | throw (IO.userError "missing imported journal")
      check ((← Journal.originalFeed journal).count == 0) "aliases were exported as original events"
      for turn in ["seed","analysis"] do
        let actual ← Journal.turnEntries journal ⟨"session",turn⟩
        let projected := values.filterMap (fun value => if value.turn.turn == turn then value.forSource target.head.identity else none)
        check (actual == projected) "lazy materialization changed exact projected original events"
        let frontier ← Journal.frontier? journal ⟨"session",turn⟩
        let latest := frontier.map (·.latest) |>.getD 0
        let complete ← Journal.completeEntries ⟨journal,⟨"session",turn⟩,latest⟩ frontier
        check (complete == projected) "metadata append receipts changed event order or body"
      let retried ← Journal.importFeed target owner ((← IO.monoMsNow)+30000)
      check (retried.complete && retried.examined == 0 && retried.added == 0 &&
        (← Journal.open? target).map (·.head) == some journal.head) "unchanged import replayed or rewrote entries"
      observations := observations.push (Json.mkObj [("elapsedMs",toJson elapsed),("result",toJson imported),
        ("exactProjectedEntries",toJson true),("originalsExported",toJson (0 : Nat))])
    check ((← DB.PageMap.pin source.directory).head == head) "ingress changed the public original head"
    reports := reports.push (Json.mkObj [("size",row.getObjValD "size"),("appendMs",toJson appendMs),
      ("targets",toJson observations),("originalHeadUnchanged",toJson true)])
  let data ← Paths.dataRoot
  save (data/"metadata-report.json") (Json.mkObj [("rows",toJson reports),("answeringModelCalls",toJson (0 : Nat))])
private def audit (root : System.FilePath) : IO Unit := do
  let inputs ← IO.ofExcept (fromJson? (← read (root/"inputs.json")) : Except String (Array Json))
  let mut steps := 0
  let mut domains := 0
  for row in inputs do
    let raw ← IO.ofExcept (row.getObjValAs? String "directory")
    let source ← DB.PageMap.pin (.mk raw)
    let values ← IO.ofExcept (row.getObjValAs? (Array Journal.Entry) "values")
    let targets ← IO.ofExcept (row.getObjValAs? (Array (String × DB.PageMap.Head)) "targets")
    let mut frontier := Journal.Frontier.initial source ⟨"literal","comparison"⟩
    let variants := values++values.reverse
    for ordinal in [:variants.size] do
      let some value := variants[ordinal]? | throw (IO.userError "missing receipt variant")
      let expected := literalStep frontier ordinal value
      check (frontier.step ordinal value == expected) "described frontier differs from literal old algorithm"
      frontier := expected
      steps := steps+1
    for value in values do
      for database in #[source.head.identity,Sha256.hex "unrelated source".toUTF8]++targets.map (·.2.identity) do
        check ((value.forSource database).isSome ==
          (value.payload.kind == "finish" || value.description.sources.contains database))
          "description changed source projection eligibility"
        domains := domains+1
  save ((← Paths.dataRoot)/"laws-report.json") (Json.mkObj [("literalReceiptSteps",toJson steps),
    ("projectionDomains",toJson domains),("allPassed",toJson true)])
private def corrupt (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve descriptor boundary fixture"
  IO.FS.createDirAll root
  let source ← Persistence.ensureSnapshot (root/"source.egg")
  let other ← Persistence.ensureSnapshot (root/"other.egg")
  let never ← Persistence.ensureSnapshot (root/"never.egg")
  let deferred ← Persistence.ensureSnapshot (root/"deferred.egg")
  let known ← Journal.knowledge source [] false
  let known := {known with related := #[⟨other.head,none⟩,⟨never.head,none⟩,⟨deferred.head,none⟩]}
  let domain := Sha256.hex "descriptor-boundary".toUTF8
  let occurrence : Occurrence := ⟨"session","turn","tool"⟩
  let values : Array Journal.Entry := #[
    ⟨⟨domain,1⟩,.start occurrence "{\"tool\":42}" domain known,none⟩,
    ⟨⟨domain,2⟩,.finish occurrence "mcp__fixture__tool" "{}" (String.ofList (List.replicate 5000 'z')) none,none⟩]
  let some finished := values[1]? | throw (IO.userError "missing finish boundary case")
  for value in values do discard <| Journal.append source value
  let owner := DB.Sidecar.Owner.ofSnapshot source
  let imported ← Journal.importFeed other owner ((← IO.monoMsNow)+30000)
  check (imported.complete && imported.added == 2) "boundary fixture did not import both original events"
  let some original ← Journal.open? source | throw (IO.userError "missing original boundary journal")
  let some received ← Journal.open? other | throw (IO.userError "missing received boundary journal")
  let described ← Journal.entryDescription original 1
  let bad := {described with sha256 := domain}
  let (_,_,_) ← DB.PageMap.withWriter original fun writer =>
    Persistence.Store.putPayload writer (Journal.descriptionKey 1) (toJson bad).compress.toUTF8
  check (← rejects (Journal.importFeed never owner ((← IO.monoMsNow)+30000)))
    "a changed description escaped the original append receipt"
  let some untouched ← Journal.open? never | throw (IO.userError "missing rejected-import journal")
  check ((← Persistence.Store.getNat untouched.get "count") == 0)
    "invalid metadata partially published its prepared prefix"
  let some damaged ← Journal.open? source | throw (IO.userError "missing damaged original")
  let (_,_,_) ← DB.PageMap.withWriter damaged fun writer =>
    Persistence.Store.putPayload writer (Journal.descriptionKey 1)
      (toJson {described with content := domain}).compress.toUTF8
  let offered ← Journal.importFeed deferred owner ((← IO.monoMsNow)+30000)
  check (offered.complete && offered.added == 2) "content-digest negative control never reached materialization"
  let some deferredJournal ← Journal.open? deferred | throw (IO.userError "missing deferred alias")
  check (← rejects (Journal.entry deferredJournal 1)) "changed content digest was usable without original validation"
  check ((← Journal.entry received 1) == finished) "a later producer head changed an old pinned alias"
  let ownDescription ← Journal.entryDescription received 1
  let (_,_,_) ← DB.PageMap.withWriter received fun writer =>
    Persistence.Store.putPayload writer (Journal.descriptionKey 1)
      (toJson {ownDescription with clock := {ownDescription.clock with nanos := 8}}).compress.toUTF8
  let some badAlias ← Journal.open? other | throw (IO.userError "missing damaged alias")
  check (← rejects (Journal.entry badAlias 1)) "alias description changed the original clock"
  check ((← Journal.entry received 1) == finished) "alias corruption changed a retained immutable reader"
  check ((← DB.PageMap.pin source.directory).head == source.head &&
    (← DB.PageMap.pin other.directory).head == other.head) "private boundary checks changed public originals"
  save (root/"report.json") (Json.mkObj [("receiptCorruptionRejectedBeforePublication",toJson true),
    ("contentCorruptionRejectedBeforeUse",toJson true),("aliasClockCorruptionRejected",toJson true),
    ("retainedOriginalAndAliasPinsExact",toJson true),("publicHeadsUnchanged",toJson true)])
def run (mode : String) (root : System.FilePath) : IO Unit := do
  if mode == "prepare" then prepare root
  else if mode == "observe" then observe root
  else if mode == "audit" then audit root
  else if mode == "corrupt" then corrupt root
  else if mode == "integration" then ProjectIngressAudit.run root
  else if mode == "replay" || mode == "prefix" then
    ReplayWorkChecks.run (if mode == "prefix" then [root.toString,"prefix"] else [root.toString])
  else throw (IO.userError "unknown metadata ingress check")
end Eggshell.Research.MetadataIngressChecks
