import Eggshell.SynapseJournal
import Eggshell.NativePublication
import Eggshell.PublicationWire
import Eggshell.SynapseRecommend

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.DB Eggshell.Persistence.Store

namespace Eggshell.Research.ProjectIngressAudit

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def sameReplay (a b : Journal.Replay) : Bool :=
  a.consumed == b.consumed && a.usage == b.usage && a.consumers == b.consumers &&
  a.pending == b.pending && a.unknown == b.unknown && a.origins == b.origins &&
  a.ambiguousNativeUses == b.ambiguousNativeUses && a.inputs == b.inputs

private def domain := Sha256.hex "project-private-ingress-check".toUTF8
private def query := Sha256.hex "query remains private".toUTF8
private def occurrence (name : String) : Occurrence := ⟨"ingress-client","turn",name⟩

private def readTool : ToolEvent := {
  name := "mcp__catalog__invoke",useId := "read",input := "{\"key\":\"one\"}"
  response := (Json.mkObj [("id",toJson "ID_ALPHA"),("tail",toJson "TAIL_BETA"),
    ("large",toJson (String.ofList (List.replicate 50000 'x')))]).compress}

private def consumer : ToolEvent := {
  name := "mcp__catalog__use",useId := "use"
  input := (Json.mkObj [("selected",toJson "ID_ALPHA"),("tail",toJson "TAIL_BETA")]).compress
  response := (toJson "CONSUMER_DONE").compress}

private def publish (source : PageMap.Snapshot) (session : String) (tool : ToolEvent) (started : Nat := 1) : IO PageMap.Snapshot := do
  let capsule : Publication.Capsule := {
    session,turn := "turn",cwd := "/controlled",work := "inspect structured originals"
    tools := #[tool],finalMessage := none,checkpoint := true
    timing := #[.interval ⟨domain,started,started+1,none⟩]}
  let request ← IO.ofExcept (capsule.prepare source.directory source.head.identity)
  let _ ← NativePublication.runPreparedAt source.directory source.directory #[request]
  return ← PageMap.pin source.directory

private def publishAnswer (source : PageMap.Snapshot) : IO PageMap.Snapshot := do
  let capsule : Publication.Capsule := {
    session := "ingress-client",turn := "turn",cwd := "/controlled",work := "inspect structured originals"
    tools := #[readTool,consumer],checkpoint := false
    finalMessage := some "Use `ID_ALPHA` together with `TAIL_BETA`."
    timing := #[.interval ⟨domain,10,11,none⟩,.interval ⟨domain,20,21,none⟩]}
  let request ← IO.ofExcept (capsule.prepare source.directory source.head.identity)
  let _ ← NativePublication.runPreparedAt source.directory source.directory #[request]
  return ← PageMap.pin source.directory

private def entries (known : Journal.Knowledge) : Array Journal.Entry := #[
  ⟨⟨domain,10⟩,.start (occurrence "read") (canonicalToolWork readTool) query known,none⟩,
  ⟨⟨domain,11⟩,.finish (occurrence "read") readTool.name readTool.input readTool.response known.archive,none⟩,
  ⟨⟨domain,20⟩,.start (occurrence "use") (canonicalToolWork consumer) query known,none⟩,
  ⟨⟨domain,21⟩,.finish (occurrence "use") consumer.name consumer.input consumer.response known.archive,none⟩,
  ⟨⟨domain,30⟩,.answer (occurrence "stop") query "Use `ID_ALPHA` together with `TAIL_BETA`." known,none⟩]

private def stats (source : PageMap.Snapshot) : IO Json := do
  let some journal ← Journal.open? source | throw (IO.userError "missing source journal")
  let count ← getNat journal.get "count"
  let mut raw := 0
  let mut references := 0
  let mut digests : Array String := #[]
  for ordinal in [:count] do
    let value ← Journal.entry journal ordinal
    digests := digests.push (Index.contentKey value)
    if (← journal.get (Journal.referenceKey ordinal)).isSome then
      references := references+1
      check ((← journal.get (PageMap.payloadChunkKey (key "entry" ordinal) 0)).isNone)
        "a referenced event also contains a local body chunk"
    else raw := raw+1
  return Json.mkObj [("rawEvents",toJson raw),("references",toJson references),
    ("digests",toJson digests),("journal",toJson journal.head)]

def inspect (root : System.FilePath) : IO Json := do
  let primary ← PageMap.pin (root/"primary.egg")
  let other ← PageMap.pin (root/"other.egg")
  let left ← stats primary
  let right ← stats other
  check (left.getObjValD "rawEvents" == toJson (6 : Nat) &&
      right.getObjValD "rawEvents" == toJson (0 : Nat) &&
      right.getObjValD "references" == toJson (5 : Nat)) "private original bodies were duplicated by source"
  return Json.mkObj [("primary",left),("other",right)]

def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute ingress root required"
  FileSystem.privateDirectory root
  let primary ← PageMap.create (root/"primary.egg") (Persistence.valueToJson (.text "private-ingress-primary")).compress
  let other ← publish (← PageMap.create (root/"other.egg")
    (Persistence.valueToJson (.text "private-ingress-other")).compress) "seed" readTool
  let _ ← Build.refresh other .database
  let known ← Journal.knowledge primary [] false (some primary.directory.toString)
  let secondary ← Journal.knowledge other [] false (some primary.directory.toString)
  let known := {known with related := #[⟨secondary.source,secondary.indexed⟩]}
  let values := entries known
  for value in values do check (← Journal.append primary value) "initial event capture was not fresh"
  let some original ← Journal.open? primary | throw (IO.userError "original ingress did not commit")
  let beforeRetry := original.head
  for value in values do check (!(← Journal.append primary value)) "identical ingress retry was appended"
  check ((← Journal.open? primary).map (·.head) == some beforeRetry) "retry advanced an immutable journal"
  let captured ← Journal.turnEntries original ⟨"ingress-client","turn"⟩
  check (captured == values) "one native capture changed original event order or bytes"
  let mapped ← values.mapM fun value =>
    match value.forSource other.head.identity with
    | some mapped => pure mapped
    | none => throw (IO.userError "configured source was omitted from captured knowledge")
  check (mapped == entries secondary) "knowledge projection differs from independently captured secondary context"
  let owner := Sidecar.Owner.ofSnapshot primary
  let mut examined := 0
  let mut added := 0
  for _ in [:3] do
    let result ← Journal.importFeed other owner ((← IO.monoMsNow)+10000) 2
    check (result.examined ≤ 2) "reference import exceeded its input row bound"
    examined := examined+result.examined
    added := added+result.added
  check (examined == 5 && added == 5) "bounded imports skipped or duplicated a native event"
  let some imported ← Journal.open? other | throw (IO.userError "source projection has no journal")
  check ((← Journal.turnEntries imported ⟨"ingress-client","turn"⟩) == mapped)
    "referenced source view differs from the independent knowledge projection"
  let reused ← Journal.importFeed other owner ((← IO.monoMsNow)+10000) 2
  check (reused.complete && reused.added == 0 && reused.examined == 0) "unchanged feed was imported again"
  let _ ← publish primary "ingress-client" readTool 10
  let _ ← publish (← PageMap.pin primary.directory) "ingress-client" consumer 20
  let primary ← publishAnswer (← PageMap.pin primary.directory)
  let _ ← Build.refresh primary .database
  let some shared ← Index.open? primary .database .shared | throw (IO.userError "primary source index unavailable")
  let sharedFacts ← Index.allFacts shared.index
  let sharedConsumed := sharedFacts.filter fun fact => match fact with | .consumed _ => true | _ => false
  let sharedSupports := sharedFacts.filter fun fact => match fact with | .supports _ => true | _ => false
  let sharedCoquoted := sharedFacts.filter fun fact => match fact with | .coquoted .. => true | _ => false
  check (!sharedConsumed.isEmpty && !sharedSupports.isEmpty)
    "original publication did not exercise shared consumption and quotation support"
  let expected ← Journal.replay other mapped ((← IO.monoMsNow)+20000)
  let actual ← Journal.replay other (← Journal.turnEntries imported ⟨"ingress-client","turn"⟩)
    ((← IO.monoMsNow)+20000)
  check (sameReplay actual expected) "referenced replay differs from complete projected original replay"
  IO.FS.writeFile (root/"replay-audit.json") ((Json.mkObj [
    ("consumed",toJson actual.consumed),("usage",toJson actual.usage),
    ("pending",toJson actual.pending),("unknown",toJson actual.unknown),
    ("ambiguous",toJson actual.ambiguousNativeUses)]).pretty++"\n")
  check (actual.consumed.isEmpty && !actual.usage.isEmpty)
    "referenced private usage was lost or promoted into foreign shared consumption"
  let refreshed ← Journal.refresh other .database ((← IO.monoMsNow)+20000)
  check (refreshed.complete) "reference journal did not complete normal background replay"
  let some usage ← UsageCache.open? other | throw (IO.userError "normal replay lost private usage")
  let used := (← Index.allFacts usage.index).filterMap fun fact => match fact with
    | .used value => some value | _ => none
  check (used.any (·.kind == .omittedThenConsumed)) "missing stored evidence lost its implicit-use label"
  let some rawReference ← imported.get (Journal.referenceKey 0) | throw (IO.userError "reference metadata missing")
  let reference ← Index.decode (α := Journal.EntryReference) rawReference
  check (← rejected (Journal.loadReference imported {reference with target := primary.head.identity}))
    "a private reference crossed its target source"
  check (← rejected (Journal.loadReference imported {reference with original := domain}))
    "a changed original digest was accepted"
  check (← rejected (Journal.loadReference imported {reference with projected := domain}))
    "a changed projected digest was accepted"
  check (← rejected (Journal.loadReference original {
    owner := Sidecar.Owner.ofSnapshot other,journal := imported.head,ordinal := 0,target := primary.head.identity,
    original := reference.original,projected := reference.projected})) "indirect private references were accepted"
  let later : Journal.Entry := ⟨⟨domain,99⟩,
    .answer ⟨"other-client","later-turn","stop"⟩ query "LATER_PRIVATE_EVENT" known,none⟩
  check (← Journal.append primary later) "later native event was not captured"
  check ((← Journal.turnEntries imported ⟨"ingress-client","turn"⟩) == mapped)
    "later original append changed a retained source reference"
  let beforeDeadline := (← Journal.open? other).map (·.head)
  let expired ← Journal.importFeed other owner (← IO.monoMsNow) 2
  check (!expired.complete && expired.examined == 0 && expired.added == 0 &&
    (← Journal.open? other).map (·.head) == beforeDeadline)
    "expired import changed the committed reference cursor"
  let some current ← Journal.open? other | throw (IO.userError "source reference journal disappeared")
  let (_,_,_) ← PageMap.withWriter current fun writer =>
    writer.put (Journal.referenceKey 0)
      (some (toJson {reference with projected := domain}).compress.toUTF8)
  let some damaged ← Journal.open? other | throw (IO.userError "damaged reference journal disappeared")
  check (← rejected (Journal.entry damaged 0)) "corrupt committed alias was accepted"
  let some firstMapped := mapped[0]? | throw (IO.userError "empty reference fixture")
  check ((← Journal.entry imported 0) == firstMapped) "alias corruption changed a retained immutable reference"
  let (_,_,_) ← PageMap.withWriter damaged fun writer =>
    writer.put (Journal.referenceKey 0) (some rawReference)
  let first ← inspect root
  let reopened ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["inspect-ingress",root.toString]}
  check (reopened.exitCode == 0 && reopened.stderr.isEmpty) "fresh-process private reference recovery failed"
  check ((← IO.ofExcept (Json.parse reopened.stdout)) == first) "fresh-process private reference view differs"
  let metadata := Json.mkObj [("allPassed",toJson true),("originalEvents",toJson values.size),
    ("referencedEvents",toJson added),("largeStructuredOutputBytes",toJson readTool.response.utf8ByteSize),
    ("replayConsumed",toJson actual.consumed.size),("replayUsage",toJson actual.usage.size),
    ("sharedConsumed",toJson sharedConsumed.size),("sharedSupports",toJson sharedSupports.size),
    ("sharedCoquoted",toJson sharedCoquoted.size),
    ("referenceProjectionExact",toJson true),("normalReplay",toJson refreshed),
    ("crossScopeAndIndirectReferencesRejected",toJson true),("corruptOriginalAndProjectedDigestsRejected",toJson true),
    ("expiredImportLeavesCursorUnchanged",toJson true),("corruptAliasRejectedOldPinUnchanged",toJson true),
    ("retainedBeforeLaterAppend",toJson true),
    ("coquotedFixture",toJson "MCP spellings produce support, not file-citation coquote facts; no three-edge capacity claim"),
    ("freshProcessSamePrivateScope",toJson true),
    ("inspect",first),("answeringModelCalls",toJson (0 : Nat)),("notCapacityOrTokenEvidence",toJson true)]
  IO.FS.writeFile (root/"report.json") (metadata.pretty++"\n")
  IO.println metadata.compress

end Eggshell.Research.ProjectIngressAudit
