import Eggshell.Warm
import Eggshell.ContractAudit
import Std.Sync.Mutex

open Lean Eggshell DB Persistence.Store

namespace Eggshell.Research.OwnedReadyAudit

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

def outcome (i : Nat) : Value := .apply .outcome (.semantic
  (.text s!"inspect kernelsignal{i}") (.semantic
    (.text (s!"original observation kernelsignal{i} " ++ String.join (List.replicate 70 "evidence "))) .nil))

def publish (source : PageMap.Snapshot) (values : List Value) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let added ← values.mapM intern.root
    writeChange writer {added,removed := [],unionsChanged := false}
  PageMap.pin source.directory

private def neutral (source : PageMap.Snapshot) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    writer.put s!"memo:{source.head.revision}" (some "neutral".toUTF8)
    writeChange writer {added := [],removed := [],unionsChanged := false}
  PageMap.pin source.directory

/-- Independent original scan, not a second invocation of the index builder. -/
def census (source : PageMap.Snapshot) : IO Json := do
  let some reader ← RetrievalResearch.Index.open? source |
    throw (IO.userError "lexical completion absent")
  let original ← NodeReader.new source
  let documents ← searchDocuments source
  let terms ← documents.mapM fun document => do
    let value ← original.outcome (← original.locateOutcome document.owner)
    return (document.owner,RetrievalResearch.tokens (searchText value))
  for term in hashDistinct (terms.flatMap Prod.snd) ++ ["w:absent"] do
    let (observed,count) ← reader.posting term
    let expected := (terms.filter (fun row => row.2.contains term)).map Prod.fst
    check (observed.mergeSort (· ≤ ·) == expected.mergeSort (· ≤ ·) && count == expected.length)
      "lexical postings differ from full original tokenization"
  let some windows ← WindowOwners.open? source .user |
    throw (IO.userError "window completion absent")
  let mut expected := []
  for document in documents do
    let ordinal ← getNat source.get (key "member" document.owner)
    expected := expected ++ WindowOwners.entries document ordinal
  let found ← WindowOwners.lookup windows (hashDistinct (expected.map Prod.fst)) 8192
  check (found.val.partialKeys.isEmpty && found.val.occurrences.length == expected.length &&
    found.val.occurrences.all expected.contains) "window postings differ from full original census"
  return Json.mkObj [("owners",toJson documents.length),("windowOccurrences",toJson expected.length),
    ("originalTokenizationAndWindowsEqual",toJson true)]

private def ownership (source : PageMap.Snapshot) : IO Json := do
  let owner := Sidecar.Owner.ofSnapshot source
  let state ← Std.Mutex.new (false,false)
  let task ← IO.asTask (Sidecar.withIndexClaim owner .lexical (fun _ => do
    state.atomically (modify fun (_,released) => (true,released))
    let deadline := (← IO.monoMsNow)+5000
    while !(← state.atomically (Prod.snd <$> get)) do
      check ((← IO.monoMsNow) < deadline) "ownership test release timed out"
      IO.sleep 1) .user) .dedicated
  try
    let deadline := (← IO.monoMsNow)+5000
    while !(← state.atomically (Prod.fst <$> get)) do
      check ((← IO.monoMsNow) < deadline) "ownership test admission timed out"
      IO.sleep 1
    Sidecar.withIndexClaim owner .windows (fun _ => pure ()) .user
    check (← rejected (Sidecar.withIndexClaim owner .lexical (fun _ => pure ()) .user))
      "two writers admitted to one lexical region"
    let childSame ← IO.Process.output {
      cmd := (← IO.appPath).toString
      args := #["claim",source.directory.toString,"lexical"]}
    check (childSame.exitCode != 0) "another process entered the occupied lexical region"
    let childIndependent ← IO.Process.output {
      cmd := (← IO.appPath).toString
      args := #["claim",source.directory.toString,"windows"]}
    check (childIndependent.exitCode == 0) "independent region was blocked across processes"
  finally
    state.atomically (modify fun (entered,_) => (entered,true))
    let _ ← IO.wait task
    pure ()
  let _ ← IO.ofExcept (← IO.wait task)
  return Json.mkObj [("independentRegionOverlapped",toJson true),("sameRegionRejected",toJson true),
    ("independentProcessOverlapped",toJson true),("sameRegionOtherProcessRejected",toJson true)]

private def retirement (root : System.FilePath) : IO Json := do
  for region in Sidecar.IndexRegion.all do
    let source ← PageMap.create (root / s!"retirement-{region.name}.egg") "retirement-original"
    let owner := Sidecar.Owner.ofSnapshot source
    let cache ← Sidecar.prepare owner .user
    let fenced ← Sidecar.withCacheClaim true do
      check (← rejected (Sidecar.withIndexClaim owner region (fun _ => pure ()) .user))
        "new region admission crossed an exclusive retirement fence"
    check fenced.isSome "could not hold retirement fence"
    Sidecar.withIndexClaim owner region (fun _ => do
      IO.FS.removeDirAll source.directory
      let blocked ← Sidecar.retireCache cache.directory source.head.identity ((← IO.monoMsNow)+1000)
      check (blocked.isNone && (← cache.directory.pathExists))
        s!"retirement passed an active {region.name} owner") .user
    let retired ← Sidecar.retireCache cache.directory source.head.identity ((← IO.monoMsNow)+1000)
    let some retired := retired | throw (IO.userError "released region prevented dead-cache retirement")
    check (!(← cache.directory.pathExists) && (← retired.pathExists)) "cache was not atomically retired"
    check (← rejected (Sidecar.withIndexClaim owner region (fun _ => pure ()) .user))
      "dead owner resurrected retired cache"
    IO.FS.removeDirAll retired
  return Json.mkObj [("allFiveRegionsBlockRetirement",toJson true),
    ("registrationToAdmissionFenced",toJson true),("releaseAllowsRetirement",toJson true),
    ("deadOwnerCannotResurrect",toJson true)]

private def scenario (root : System.FilePath) : IO Json := do
  let base ← PageMap.create (root / "source.egg") "owned-ready-original"
  let earlier ← publish base (List.range 8 |>.map outcome)
  let later ← publish earlier [outcome 8]
  let ownership ← ownership earlier
  let retirement ← retirement root
  let _ ← Warm.prepareSourceIndexes earlier .user
  let first ← census earlier
  check (!(← RetrievalResearch.Index.ready later) && (← WindowOwners.open? later .user).isNone)
    "old completion certified changed source"
  let some oldReader ← RetrievalResearch.Index.open? earlier | throw (IO.userError "old reader absent")
  let _ ← Warm.prepareSourceIndexes later .user
  let second ← census later
  let _ ← census earlier
  let term := (RetrievalResearch.tokens "kernelsignal0").head!
  check ((← oldReader.posting term).2 == 1) "pinned reader changed after later completion"
  let workspace ← PageMap.pin (← RetrievalResearch.Index.path later .user)
  let some view ← PreparedRoot.read? later workspace (PreparedRoot.key later.head) |
    throw (IO.userError "named completion absent")
  let ready := PreparedRoot.path workspace
  IO.FS.removeFile (ready / "latest")
  PreparedRoot.publish later workspace
  check ((← PreparedRoot.read? later workspace "latest") == some view)
    "retry after named publication failed to repair latest"
  let some oldRoot ← PreparedRoot.select? earlier workspace | throw (IO.userError "old index unavailable")
  PreparedRoot.publish earlier oldRoot
  check ((← PreparedRoot.read? later workspace "latest") == some view) "latest moved backward"
  let file := ready / PreparedRoot.key later.head
  let valid ← IO.FS.readBinFile file
  let stored := PreparedRoot.Stored.ofView later.head workspace.head view
  let corrupt := {stored with checksum := "corrupt"}
  FileSystem.atomicExistingBytes file (toJson corrupt).compress.toUTF8
  check (!(← RetrievalResearch.Index.ready later)) "corrupt checksum certified readiness"
  FileSystem.atomicExistingBytes file valid
  let foreign : PreparedRoot.Stored := {stored with view :=
    {view with source := {view.source with identity := base.head.identity ++ "foreign"}}}
  let foreign := {foreign with checksum := PreparedRoot.checksumFor foreign.owner foreign.view}
  FileSystem.atomicExistingBytes file (toJson foreign).compress.toUTF8
  check (!(← RetrievalResearch.Index.ready later)) "foreign original certified readiness"
  FileSystem.atomicExistingBytes file valid
  let badAuthority := {later with head := {later.head with authority := "foreign"}}
  check (← rejected (PreparedRoot.publish badAuthority workspace)) "foreign source authority published"
  let badFork := {view with source := {view.source with bytes := view.source.bytes+1}}
  PreparedRoot.install later workspace "latest" badFork
  IO.FS.removeFile file
  check (!(← RetrievalResearch.Index.ready later)) "divergent lineage certified source"
  FileSystem.atomicExistingBytes file valid
  PreparedRoot.install later workspace "latest" view
  FileSystem.atomicExistingBytes file (String.ofList (List.replicate 16385 'x')).toUTF8
  check (!(← RetrievalResearch.Index.ready later)) "oversized record certified readiness"
  FileSystem.atomicExistingBytes file valid
  FileSystem.atomicExistingBytes file (valid ++ " ".toUTF8)
  check (!(← RetrievalResearch.Index.ready later)) "noncanonical record certified readiness"
  FileSystem.atomicExistingBytes file valid
  let mut tail := later
  for _ in [:PreparedRoot.capacity+5] do
    tail ← neutral tail
    PreparedRoot.publish tail workspace
  let _ ← census tail
  check ((← oldReader.posting term).2 == 1) "active reader was invalidated by slot rollover"
  let entries ← ready.readDir
  check (entries.size == PreparedRoot.capacity+1 &&
    entries.all (fun entry => entry.fileName == "latest" || entry.fileName.startsWith "view-"))
    "ready slot inventory grew beyond capacity"
  let current ← PageMap.pin earlier.directory
  check (current.head == tail.head) "index preparation modified original head"
  return Json.mkObj [("ownership",ownership),("retirement",retirement),("earlier",first),("later",second),
    ("namedAndNeutralRestoration",toJson true),("oldReadersRetained",toJson true),
    ("partialPublicationRecovered",toJson true),("latestNeverRolledBack",toJson true),
    ("checksumScopeAuthorityForkSizeAndEncodingRejected",toJson true),
    ("boundedReadyFiles",toJson entries.size),("finalHead",toJson tail.head)]

end Eggshell.Research.OwnedReadyAudit

def main (args : List String) : IO Unit := do
  if let ["warm-probe",targetFile] := args then
    let target ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk targetFile)) >>= fromJson? (α := Plugin.IndexTarget))
    let snapshot ← target.owner.pin
    IO.println "stage journal"
    let (snapshot,_) ← Warm.refreshSource snapshot target.storage ((← IO.monoMsNow)+60000)
    IO.println "stage canonical"
    let _ ← Synapses.CanonicalSource.Cache.refresh snapshot target.storage
    IO.println "stage windows"
    let _ ← WindowOwners.refresh snapshot target.storage
    IO.println "stage lexical"
    let _ ← RetrievalResearch.Index.warm snapshot target.storage
    IO.println "stage parallel"
    let _ ← Warm.prepareSourceIndexes snapshot target.storage
    IO.println "stage remaining warm"
    let result ← Warm.runTarget snapshot target
    IO.println (toJson result).compress
    return
  if let ["claim",directory,region] := args then
    let source ← PageMap.pin (.mk directory)
    let region ← match region with
      | "lexical" => pure Sidecar.IndexRegion.lexical
      | "windows" => pure Sidecar.IndexRegion.windows
      | _ => throw (IO.userError "invalid ownership test region")
    Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) region (fun _ => pure ()) .user
    return
  if let ["inspect",directory] := args then
    let result ← Eggshell.Research.OwnedReadyAudit.census (← PageMap.pin (.mk directory / "source.egg"))
    IO.println result.compress
    return
  let [directory] := args | throw (IO.userError "OwnedReadyAudit NEW_ROOT")
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "fresh absolute root required")
  FileSystem.privateDirectory root
  let started ← IO.monoMsNow
  let result ← Eggshell.Research.OwnedReadyAudit.scenario root
  let reopened ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["inspect",root.toString]}
  unless reopened.exitCode == 0 do
    throw (IO.userError s!"fresh-process reopen failed: {reopened.stdout}{reopened.stderr}")
  let result := result.setObjVal! "freshProcessReopen" (toJson true)
  let result := result.setObjVal! "elapsedMs" (toJson ((← IO.monoMsNow)-started))
  IO.FS.writeFile (root / "result.json") (result.pretty ++ "\n")
  IO.println result.compress
