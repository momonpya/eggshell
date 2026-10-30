import Eggshell.SynapseBuild
import Eggshell.ContentMetadata
import Eggshell.SynapticBindings
import tools.research.SourceBindingReference
open Lean Eggshell Eggshell.Synapses

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal actual owner inventory"
  return (result.stdout.splitOn " ").headD ""

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "fresh actual inventory directory required")
  let root : System.FilePath := .mk output
  check (!(← root.pathExists)) "preserve completed real inventory experiment"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let shared := study / "shared-snapshot"
  let original ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let data := DB.PageMap.dataPath original.directory original.head
  let originals := #[(original.directory / "head",← hash (original.directory / "head")),(data,← hash data)]
  let database := root / "work.egg"
  IO.FS.createDirAll database
  for (file,_) in originals do
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",file.toString,(database / file.fileName.get!).toString]}
    check (copied.exitCode == 0) "cannot clone the fixed original source"
  let source ← DB.PageMap.pin database
  check (source.head == original.head) "fork changed the saved source snapshot"
  let refined ← read (shared / "anchored-capture/seed-refinement.json")
  check (refined.getObjValD "source" == toJson source.head) "supplement crossed source publication"
  let entries : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept (refined.getObjValAs? _ "supplements")
  let nodes ← Persistence.Store.NodeReader.new source
  let mut supplements := #[]
  for (id,owner,value) in entries do
    check ((← Build.document nodes id).owner == owner) "supplement changed its original owner"
    if value.sealed then supplements := supplements.push (id,value)
  let prepared ← Build.refresh source .database supplements
  IO.FS.writeFile (root / "preparation.json") (toJson prepared).pretty
  let some current ← Index.open? source .database .shared | throw (IO.userError "actual owner inventory missing")
  let legacyCount ← current.index.foldRange ⟨"binding:","binding;"⟩ (fun n _ => pure (n+1)) (0 : Nat)
  check (legacyCount == 0) "actual producer retained source point bindings"
  let facts ← Index.allFacts current.index
  let candidates := facts.filterMap Index.bindingCandidate?
  let wanted := (hashDistinct (candidates.toList.filter (·.source.file?.isSome) |>.map (·.source))).toArray
  let allowed := candidates.foldl (fun found item => found.insert item.binding.owner) ({} : Std.HashSet String)
  check (!wanted.isEmpty && !allowed.isEmpty) "actual binding domain was empty"
  let reference ← DB.PageMap.create (root / "reference.egg") "independent-source-point-inventory"
  let _ ← DB.PageMap.withWriter reference fun writer => do
    for fact in facts do
      if let some value := Index.bindingCandidate? fact then
        let stored : Index.StoredBinding := ⟨Index.contentKey fact,value⟩
        writer.put ("binding:" ++ Index.contentKey value.source ++ ":" ++ stored.fact)
          (some (toJson stored).compress.toUTF8)
  let reference ← DB.PageMap.pin reference.directory
  let oldPages ← DB.PageMap.PagePool.new
  let newPages ← DB.PageMap.PagePool.new
  let oldReader : Index.Reader := ⟨← reference.sharePages oldPages "source-point-reference",current.manifest⟩
  let newReader := {current with index := ← current.index.sharePages newPages "owner-inventory-candidate"}
  IO.FS.writeFile (root / "protocol.json") (Json.mkObj [("source",toJson source.head),
    ("sourceFiles",toJson (originals.map fun (path,digest) => (path.toString,digest))),
    ("factCount",toJson facts.size),("requests",toJson wanted.size),("owners",toJson allowed.size),
    ("order",toJson #["source-0","owner-0","owner-1","source-1"]),
    ("referenceContainsOnlySourcePointProjection",toJson true),("newPagePoolPerArmThenReused",toJson true),
    ("offlineWholeInventoryNotActualHook",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let mut expected : Option (Std.HashMap Range (Array Read)) := none
  let mut samples := #[]
  for (candidate,repetition) in [(false,0),(true,0),(true,1),(false,1)] do
    let started ← IO.monoMsNow
    let deadline := started+300000
    let result ← if candidate then IndexedBindings.resolve newReader wanted allowed deadline else do
      let found ← Research.SourceBindingReference.resolve oldReader wanted allowed deadline
      pure ({
        rows := found.rows
        complete := found.complete
        requests := found.requests
        inspected := found.inspected
        bytes := found.bytes
        unresolved := found.unresolved
        unusable := found.unusable} : IndexedBindings.Resolved)
    let elapsed := (← IO.monoMsNow)-started
    check (result.complete && result.requests == wanted.size && result.rows.size == wanted.size)
      "actual inventory was partial"
    if let some prior := expected then
      check (prior.toArray.all (fun (key,value) => result.rows[key]? == some value)) "actual original Read sequence changed"
    else expected := some result.rows
    let sample := Json.mkObj [("candidate",toJson candidate),("repetition",toJson repetition),
      ("elapsedMs",toJson elapsed),("matchedBytes",toJson result.bytes),("inspected",toJson result.inspected),
      ("requests",toJson result.requests),("sameOrderedReads",toJson true)]
    samples := samples.push sample
    IO.FS.writeFile (root / "progress.json") (toJson samples).pretty
    IO.println sample.compress
  for (path,digest) in originals do check ((← hash path) == digest) "actual audit changed protected source bytes"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("samples",toJson samples),
    ("sameAllRequestedReadSequences",toJson true),("sourceUnchanged",toJson true),
    ("sourcePagePool",← oldPages.stats),("ownerPagePool",← newPages.stats),
    ("actualHook",toJson false),("deliveryRecallMeasured",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
