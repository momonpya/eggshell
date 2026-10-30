import tools.research.PrivateRoutingView
import tools.research.RoutingScopeReference
import Eggshell.SynapseBuild
import Eggshell.SynapticTransport

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Routing

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool :=
  try let _ ← action; pure false catch _ => pure true
private def view (source : DB.PageMap.Snapshot) (storage : DB.Sidecar.Storage) (scope : Index.Scope) : IO Store.Reader := do
  let some index ← Index.open? source storage scope | throw (IO.userError "fixture index is missing")
  let some ready ← Store.open? index | do
    let stamp ← (← index.index.get "route:implementation").mapM (Index.decode (α := String))
    let counts ← (← index.index.get "route:counts").mapM (Index.decode (α := Store.Counts))
    throw (IO.userError s!"fixture routing is cold: {(toJson (scope,index.manifest.facts,stamp == some Store.implementation,counts)).compress}")
  return ready
private def fingerprint (walk : Store.Walk) : Json := Json.mkObj [
  ("hints",toJson (walk.hints.map Store.Hint.json)),("groups",toJson (walk.hints.map (·.group))),
  ("nodes",toJson walk.nodes),("arcs",toJson walk.arcs),("bytes",toJson walk.bytes),("complete",toJson walk.complete)]

private def compare (shared : Store.Reader) (usage : Store.Reader) (capsule : PrivateView.Capsule)
    (roots : Array (Index.Key × Nat)) (deadline : Nat) : IO Json := do
  let wire := (toJson capsule).compress
  let restored ← IO.ofExcept (Json.parse wire >>= fromJson? (α := PrivateView.Capsule))
  let retained ← restored.prepare
  let original ← Store.referenceWalk shared (some usage) roots deadline
  let ordinary ← Store.walk shared (some usage) roots deadline
  let remote ← Store.walkUsing shared.readView (some retained.readView) roots deadline
  let expected := fingerprint original
  check (original.complete && ordinary.complete && remote.complete) "routing comparison did not finish"
  check (fingerprint ordinary == expected && fingerprint remote == expected)
    "read-view/capsule routing changed original order, groups, priorities, counters or targets"
  check ((Routed.preferOmissions original.hints).map Store.Hint.json ==
    (Routed.preferOmissions remote.hints).map Store.Hint.json) "private omission precedence changed"
  return Json.mkObj [("wireBytes",toJson wire.utf8ByteSize),("hints",toJson original.hints.size),
    ("nodes",toJson original.nodes),("arcs",toJson original.arcs),("bytes",toJson original.bytes),
    ("sameOriginalLoop",toJson true),("walkSha256",toJson (Sha256.hex expected.compress.toUTF8))]

private def usageFact (query : String) (source : Range) (label : UsageKind) (session : String) : Fact :=
  .used {event := {occurrence := ⟨session,"turn","read"⟩,ordinal := 0},query,source,kind := label}

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh routing audit directory required")
  let root : System.FilePath := .mk destination
  check (!(← root.pathExists)) "preserve earlier routing scope audit"
  IO.FS.createDir root
  let source ← DB.PageMap.create (root / "source.egg") "private-routing-scope"
  let before := source.head
  let file : File := ⟨"source.cpp",String.ofList (List.replicate 64 'a'),100⟩
  let first : Range := ⟨.file file,10,10⟩
  let second : Range := ⟨.file file,20,20⟩
  let third : Range := ⟨.file file,30,30⟩
  let group := Group.answer source.head.identity (Persistence.selectionKey (.text "one original answer"))
  let other := Group.answer source.head.identity (Persistence.selectionKey (.text "another original answer"))
  let _ ← Index.replace source .database .shared #[.coquoted group first,.coquoted group second,.coquoted other third]
  let shared ← view source .database .shared
  let query := Sha256.hex "same requested question".toUTF8
  let absent := Sha256.hex "absent question".toUTF8
  let facts := #[usageFact query first .omittedThenRead "caller-a",
    usageFact query first .deliveredThenCited "caller-a-cited"]
  let _ ← Index.replace source .user .usage facts
  let a ← view source .user .usage
  let deadline := (← IO.monoMsNow)+60000
  let ca ← PrivateView.capture a #[query,absent,query] deadline
  let _ ← Index.replace source .user .usage #[usageFact query third .omittedThenConsumed "caller-b"]
  let b ← view source .user .usage
  let cb ← PrivateView.capture b #[query,absent] deadline
  let roots := #[(Index.Key.query query,0),(.group group,7),(.quoted first,9),(.query absent,3)]
  let ra ← compare shared a ca roots deadline
  let rb ← compare shared b cb roots deadline
  check (ra.getObjValD "walkSha256" != rb.getObjValD "walkSha256") "two caller overlays collapsed"
  let privateA ← ca.prepare
  let privateB ← cb.prepare
  let originalA ← Store.referenceWalk shared (some a) roots deadline
  let originalB ← Store.referenceWalk shared (some b) roots deadline
  let ready ← IO.mkRef false
  let tasks ← (Array.range 80).mapM fun client => IO.asTask (do
    while !(← ready.get) do IO.sleep 1
    let selected := if client%2 == 0 then privateA else privateB
    let expected := if client%2 == 0 then originalA else originalB
    let start ← IO.monoMsNow
    let found ← Store.walkUsing shared.readView (some selected.readView) roots deadline
    check (fingerprint found == fingerprint expected) "concurrent private routing leaked, changed order or lost a target"
    return (← IO.monoMsNow)-start) .dedicated
  ready.set true
  let times ← tasks.mapM fun task => IO.ofExcept (task.get.mapError IO.Error.toString)
  check (← rejected (PrivateView.capture shared #[query] deadline)) "shared index accepted as private usage"
  check (← rejected ({ca with manifest := {ca.manifest with scope := .shared}}.prepare)) "shared capsule accepted"
  let some firstValue := ca.values[0]? | throw (IO.userError "private fixture has no destination")
  check (← rejected ({ca with values := ca.values.push firstValue}.prepare)) "duplicate capsule destination accepted"
  let some firstScan := ca.scans[0]? | throw (IO.userError "private fixture has no scan")
  let some firstArc := firstScan.2.arcs[0]? | throw (IO.userError "private fixture has no arc")
  let badScan := {firstScan.2 with arcs := firstScan.2.arcs.set! 0 {firstArc with group := some 0}}
  check (← rejected ({ca with scans := ca.scans.set! 0 (firstScan.1,badScan)}.prepare)) "private capsule forged a joint group"
  check (← rejected (privateA.readView.locate (.group group))) "private capsule accepted a non-query root"
  check (← rejected (privateA.readView.locate (.query (Sha256.hex "not captured".toUTF8)))) "uncaptured private root became empty success"
  let tiny ← Store.walkUsing shared.readView (some privateA.readView) roots deadline {bytes := 0}
  check (!tiny.complete && tiny.hints.isEmpty) "inadequate routing budget became a successful empty"
  let noPrivate ← Store.walk shared none roots deadline
  check (noPrivate.hints.all (fun hint => hint.kind != 3 && hint.kind != 4 && hint.kind != 5))
    "private feedback persisted in shared routing"
  let foreign ← DB.PageMap.create (root / "foreign.egg") "foreign routing source"
  let foreignGroup := Group.answer foreign.head.identity (Persistence.selectionKey (.text "foreign original answer"))
  let _ ← Index.replace foreign .database .shared #[.coquoted foreignGroup first]
  let foreignView ← view foreign .database .shared
  check (← rejected (Store.walkUsing foreignView.readView (some privateA.readView) roots deadline))
    "private capsule crossed a project boundary"
  check ((← DB.PageMap.pin source.directory).head == before) "private routing mutated the primary source"
  let sorted := times.qsort (· < ·)
  let result := Json.mkObj [("callerA",ra),("callerB",rb),("clients",toJson times.size),
    ("p50Ms",toJson sorted[39]!),("p95Ms",toJson sorted[75]!),("maxMs",toJson sorted[79]!),
    ("sameSourceDifferentCallers",toJson true),("foreignSourceRejected",toJson true),
    ("malformedScopeAndGroupRejected",toJson true),("oldPrivateSnapshotPreserved",toJson true),
    ("sharedUsageNotWritten",toJson true),("primarySourceUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("actualHookMeasured",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root / "results.json") result.pretty
  IO.println result.compress
