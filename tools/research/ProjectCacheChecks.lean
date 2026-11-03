import Eggshell.PluginCli
import Eggshell.DB.CacheReclaim
import Eggshell.KeyedSearchProvider
import tools.research.ProjectContextChecks

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.ProjectStore

run_meta do
  for name in [``PartitionBuild.selectSample,``PartitionBuild.rebuild] do
    let info ← getConstInfo name
    let some body := info.value? | throwError "source preparation is not auditable: {name}"
    let used := body.getUsedConstants
    unless used.contains ``ProjectionCursor.foldKeys do
      throwError "source preparation lost its bounded source-key traversal: {name}"
    if used.contains ``ProjectionCursor.fold || used.contains ``ProjectionCursor.catalogue then
      throwError "source preparation scans the project matrix: {name}"

namespace Eggshell.Research.ProjectCacheChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def key (name : String) := Sha256.hex name.toUTF8
private def scalar := "000000000000f03f0000000000000000"
private def coverage := (toJson (⟨1,1,1,1,1,1,128,16,true⟩ : SearchProvider.EncodingCoverage)).compress

private def matrix (root : System.FilePath) (keys : List String) : IO VectorMatrix.Result :=
  VectorMatrix.ensureUsing root MiniLM.model SearchProvider.encoderContract keys fun item =>
    return ⟨item,coverage,scalar⟩

private def opened (root : System.FilePath) : IO VectorMatrix.Ready := do
  let some ready ← VectorMatrix.open? root MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "shared projection matrix missing")
  return ready

private def publish (project : Project) (slot : Nat) (marker : String) : IO PageMap.Snapshot := do
  withOwner project slot fun owner => do
    let pending : PendingTurn := {
      sessionId := s!"cache-{slot}",turnId := marker,cwd := project.directory.toString,
      prompt := "inspect cache evidence",profile := "fixture",semanticMatcher := none,
      read := [project.directory.toString],write := some project.directory.toString,
      handoffChars := 120000,projection := .automatic,
      tools := [{
        name := "mcp__fixture__inspect",useId := marker
        input := (Json.mkObj [("key",toJson marker)]).compress,
        response := (Json.mkObj [("id",toJson marker),("evidence",toJson s!"ORIGINAL_{marker}")]).compress}] }
    let prepared ← owner.prepare pending
    let view ← pin project ((← IO.monoMsNow)+20000)
    let _ ← owner.publish view #[prepared]
    project.current slot

private def sourceRouting (project : Project) (firstSide : Sidecar) : IO Json := do
  let first ← publish project 0 "FIRST"
  let firstKeys := (← SourceCatalogue.references first).toList.map Prod.fst
  check (!firstKeys.isEmpty) "native source has no routing candidates"
  let firstAdded ← matrix firstSide.semantic firstKeys
  let before ← opened firstSide.semantic
  let preparedFirst ← PartitionBuild.prepare firstSide.semantic MiniLM.model SearchProvider.encoderContract first before
  let some retained ← PartitionBuild.read? firstSide.semantic MiniLM.model SearchProvider.encoderContract first |
    throw (IO.userError "first source route was not prepared")
  let second ← publish project 1 "SECOND"
  let secondSide ← Sidecar.prepare (Sidecar.Owner.ofSnapshot second)
  let secondKeys := (← SourceCatalogue.references second).toList.map Prod.fst
  let secondAdded ← matrix secondSide.semantic secondKeys
  let afterMatrix ← opened secondSide.semantic
  let preparedSecond ← PartitionBuild.prepare secondSide.semantic MiniLM.model SearchProvider.encoderContract second afterMatrix
  let some restored ← PartitionBuild.read? firstSide.semantic MiniLM.model SearchProvider.encoderContract first |
    throw (IO.userError "another source's preparation removed the old route")
  check (restored.matrix.snapshot.head == retained.matrix.snapshot.head &&
    restored.partition.snapshot.head == retained.partition.snapshot.head)
    "source routing reopened a later project matrix"
  let expected ← ProjectionCursor.fold afterMatrix (fun keys row =>
    pure (if firstKeys.contains row.key then keys.push row.key else keys)) (#[] : Array String)
  let selected ← ProjectionCursor.foldKeys afterMatrix firstKeys
    (fun keys row => pure (keys.push row.key)) (#[] : Array String)
  check (selected == expected && selected.size == firstKeys.length)
    "source-only matrix traversal differs from full directory reference"
  check (← rejected (ProjectionCursor.foldKeys afterMatrix [key "ABSENT"] (fun n _ => pure (n+1)) (0 : Nat)))
    "absent source projection was skipped"
  check (← rejected (ProjectionCursor.foldKeys afterMatrix [key "shared",key "shared"]
    (fun n _ => pure (n+1)) (0 : Nat))) "duplicate source projection was admitted"
  check (PartitionBuild.folder firstSide.semantic MiniLM.model SearchProvider.encoderContract first !=
    PartitionBuild.folder secondSide.semantic MiniLM.model SearchProvider.encoderContract second)
    "different source routes overwrite the same workspace"
  return Json.mkObj [("first",toJson firstAdded),("second",toJson secondAdded),
    ("firstRoute",toJson preparedFirst),("secondRoute",toJson preparedSecond),
    ("sourceKeys",toJson firstKeys.length),("projectRows",toJson afterMatrix.metadata.rows),
    ("fullDirectoryReferenceAgrees",toJson true),("retainedOldMatrixAndRoute",toJson true)]

private def layout (root : System.FilePath) : IO Json := do
  let project ← create (root/"work.project") 3
  let other ← create (root/"other.project") 2
  let readOnly ← create (root/"readonly.project") 2
  let readOnlySources ← (List.range 2).toArray.mapM readOnly.current
  let readOnlyCaches ← readOnlySources.mapM fun source => Sidecar.destination (Sidecar.Owner.ofSnapshot source) false
  check (!(← (readOnly.directory/"derived").pathExists) &&
    readOnlyCaches.all (fun (storage,_) => storage == .user)) "read-only preparation wrote inside the shared project"
  let sources ← (List.range 3).toArray.mapM project.current
  let sides ← sources.mapM fun source => Sidecar.prepare (Sidecar.Owner.ofSnapshot source)
  let some firstSide := sides[0]? | throw (IO.userError "missing fixture source")
  check (sides.all (·.semantic == firstSide.semantic) && sides.all (·.root == firstSide.root) &&
    (sides.toList.map (·.directory)).Nodup) "canonical cache was copied by owner"
  let originals := sources.map (·.head)
  let privateSides ← sources.mapM fun source => (Sidecar.destination (Sidecar.Owner.ofSnapshot source) false)
  let privateSide := privateSides[0]?.map Prod.snd
  let some privateSide := privateSide | throw (IO.userError "missing private fixture source")
  check (privateSides.all (fun (storage,side) => storage == .user && side.semantic == privateSide.semantic) &&
    privateSide.semantic != firstSide.semantic) "read-only project overlay is not scope-shared"
  let otherSource ← other.current 0
  let otherSide ← Sidecar.prepare (Sidecar.Owner.ofSnapshot otherSource)
  check (otherSide.semantic != firstSide.semantic) "different project caches were joined"
  for (source,head) in sources.zip originals do
    check ((← PageMap.pin source.directory).head == head) "cache preparation changed an original source"
  let firstAdded ← matrix firstSide.semantic [key "one",key "shared"]
  let before ← opened firstSide.semantic
  let secondAdded ← matrix firstSide.semantic [key "two",key "shared"]
  let afterMatrix ← opened firstSide.semantic
  check (firstAdded.produced == 2 && secondAdded.produced == 1 && afterMatrix.metadata.rows == 3)
    "shared numerical payload was duplicated"
  check ((← VectorMatrix.read before (key "two")).isNone &&
    (← VectorMatrix.read before (key "shared")).isSome &&
    (← VectorMatrix.read afterMatrix (key "two")).isSome) "shared append changed the old matrix view"
  let some source := sources[0]? | throw (IO.userError "missing first source")
  let some another := sources[1]? | throw (IO.userError "missing second source")
  Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) .semantic (fun _ => do
    check (← rejected (Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot another) .semantic (fun _ => pure ())))
      "two preparers acquired the same canonical writer region"
    Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot another) .lexical (fun _ => pure ())
    let published ← publish project 2 "DURING_SEMANTIC_PREPARATION"
    check (published.head.revision > 0) "canonical preparation blocked independent original publication")
  let raw ← IO.FS.readBinFile (project.directory/"cache-scope")
  let scope ← ProjectCacheScope.read project.directory
  FileSystem.atomicExistingBytes (project.directory/"cache-scope")
    (toJson {scope with inventory := key "foreign-inventory"}).compress.toUTF8
  check (← rejected (openProject project.directory)) "foreign cache inventory was accepted"
  FileSystem.atomicExistingBytes (project.directory/"cache-scope") raw
  FileSystem.atomicExistingBytes (project.directory/"cache-scope")
    (toJson {scope with authority := "foreign"}).compress.toUTF8
  check (← rejected (Sidecar.locate source .database)) "foreign cache authority was accepted"
  FileSystem.atomicExistingBytes (project.directory/"cache-scope") raw
  let routes ← sourceRouting project firstSide
  let privateOther ← Sidecar.prepare (Sidecar.Owner.ofSnapshot otherSource) .user
  let anotherOther ← other.current 1
  let _ ← Sidecar.prepare (Sidecar.Owner.ofSnapshot anotherOther) .user
  check ((← Sidecar.retireCache privateOther.root other.manifest.identity ((← IO.monoMsNow)+5000)).isNone)
    "live shared project cache was retired"
  IO.FS.removeDirAll otherSource.directory
  check ((← Sidecar.retireCache privateOther.root other.manifest.identity ((← IO.monoMsNow)+5000)).isNone)
    "cache was retired while another owner was alive"
  Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot anotherOther) .lexical (fun _ => do
    IO.FS.removeDirAll anotherOther.directory
    check ((← Sidecar.retireCache privateOther.root other.manifest.identity ((← IO.monoMsNow)+5000)).isNone)
      "shared cache was retired while a source preparer held its region") .user
  check ((← Sidecar.retireCache privateOther.root other.manifest.identity ((← IO.monoMsNow)+5000)).isSome)
    "ended shared cache could not be retired"
  return Json.mkObj [("sameCanonicalAcrossOwners",toJson true),("sourceMetadataSeparated",toJson true),
    ("differentProjectsSeparated",toJson true),("readOnlyOverlayShared",toJson true),
    ("numericalDedup",toJson secondAdded),("originalPublicationDuringPreparation",toJson true),
    ("descriptorCorruptionRejected",toJson true),("safeSharedRetirement",toJson true),
    ("routing",routes)]

private def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute cache fixture root required"
  FileSystem.privateDirectory root
  let started ← IO.monoMsNow
  let result ← layout root
  let report := Json.mkObj [("allPassed",toJson true),("checks",result),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("answeringModelCalls",toJson (0 : Nat)),
    ("realEmbeddingModelUsed",toJson false),("eightyPersonCapacity",toJson false),
    ("productionAdoption",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

private def prepareContext (root : System.FilePath) : IO Unit := do
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "preparation lost the captured project boundary")
  let some write := context.selection.write | throw (IO.userError "preparation lost its logical write scope")
  let before ← write.project.current write.slot.val
  let targets ← registeredIndexTargets
  check (targets.any (fun (_,target) => target.owner.database == before.head.identity))
    "normal save did not persist a physical preparation target"
  let started ← IO.monoMsNow
  try
    flushIndexes pending.sessionId ((← IO.monoMsNow)+60000)
    for (_,target) in targets do
      if target.owner.database != before.head.identity then continue
      let source ← target.owner.pin
      check (!(← Warm.required target source)) "normal background worker left its source cold"
      let directory ← target.indexes source
      let entries ← if ← directory.pathExists then directory.readDir else pure #[]
      check (!(entries.any (·.fileName.endsWith ".json"))) "normal background worker left the publication ticket pending"
    check ((← write.project.current write.slot.val).head == before.head) "preparation advanced the original source"
    -- Terminal commands resolve the same logical project; no answering model is started.
    IO.FS.writeFile (root/".eggshell.toml") (← IO.FS.readFile (root/"eggshell.toml"))
    let warmed ← IO.Process.output {
      cmd := (← IO.appPath).toString
      args := #["egg","warm",write.project.directory.toString],cwd := some root}
    check (warmed.exitCode == 0) s!"logical project warm failed: {warmed.stderr}"
    let warmJson ← IO.ofExcept (Json.parse warmed.stdout)
    let databases ← IO.ofExcept (warmJson.getObjValAs? (Array Json) "databases")
    check (databases.size == 1) "logical warm split one project into user databases"
    let some database := databases[0]? | throw (IO.userError "logical warm omitted its project")
    let rows ← IO.ofExcept (database.getObjValAs? (Array Json) "sources")
    check (rows.size == write.project.manifest.owners.size) "logical warm omitted a physical owner"
    let doctor ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["egg","doctor"],cwd := some root}
    check (doctor.exitCode == 0) s!"logical doctor failed: {doctor.stderr}"
    let status ← IO.ofExcept (Json.parse doctor.stdout)
    let statuses ← IO.ofExcept (status.getObjValAs? (Array Json) "databases")
    let some work := statuses.find? (fun item => (item.getObjValAs? String "name").toOption == some "work") |
      throw (IO.userError "doctor omitted its logical write project")
    check ((work.getObjValAs? String "state").toOption == some "warm") "doctor did not report the prepared project"
    let report := Json.mkObj [("allPassed",toJson true),("normalSaveTargetDrained",toJson true),
      ("sourceHeadUnchanged",toJson true),("logicalWarmSources",toJson rows.size),
      ("logicalDoctorWarm",toJson true),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
      ("answeringModelCalls",toJson (0 : Nat)),("eightyPersonCapacity",toJson false)]
    IO.FS.writeFile (root/"preparation-report.json") (report.pretty++"\n")
    IO.println report.compress
  finally Worker.shutdown

end Eggshell.Research.ProjectCacheChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | "context" :: rest => projectContextCommand rest
  | ["prepare-context",root] => Eggshell.Research.ProjectCacheChecks.prepareContext (.mk root); return 0
  | ["codex-numerical-daemon",model,models,python] => Eggshell.Numerical.serve ⟨model,.mk models,.mk python⟩
  | ["codex-numerical-client",model,models,python] => Eggshell.Numerical.proxy ⟨model,.mk models,.mk python⟩
  | "search-provider" :: rest => Eggshell.SearchProvider.run rest
  | "keyed-search-provider" :: rest => Eggshell.KeyedSearchProvider.run rest
  | ["egg","warm",path] => IO.println (← Eggshell.Plugin.warm (some path)); return 0
  | ["egg","doctor"] => IO.println (← Eggshell.Plugin.doctor); return 0
  | ["codex-publication-daemon"] | ["serve"] => Eggshell.Plugin.Publication.Service.run
  | ["codex-worker",role] => Eggshell.Plugin.Worker.run role
  | ["inspect-context",_] | ["diagnose-context",_] | ["owners80",_] | ["inspect",_] => projectContextCommand args
  | [root] => Eggshell.Research.ProjectCacheChecks.run (.mk root); return 0
  | _ => throw (IO.userError "ProjectCacheChecks ROOT | context ROOT | owners80 ROOT")
