import Eggshell.CandidateDomain
import Eggshell.PluginModel

open Lean Eggshell Eggshell.CandidateDomain Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def native (id : String) : Value :=
  let tool : Plugin.ToolEvent := {
    name := "catalog"
    useId := id
    input := (Json.mkObj [("item",toJson id)]).compress
    response := (Json.mkObj [("id",toJson id),("status",toJson "open")]).compress }
  (Plugin.compileOperationOutcomes (.text "seed") (.text "turn") tool).2

private def publish (source : Snapshot) (values : List Value) : IO Snapshot := do
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    writeChange writer ⟨ids,[],false⟩
  DB.PageMap.pin source.directory

private def summary (documents : List SearchDocument) : List (Nat × Nat × List String) :=
  documents.map fun row => (row.owner,row.work,row.windows)

private def scenario (root : System.FilePath) : IO Unit := do
  let initial ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "authority")).compress
  let a := native "one"
  let b := native "two"
  let plain ← IO.ofExcept (Plugin.relation? .outcome [.semantic (.text "通常のWork"),.semantic (.text "plain result")])
  let some ownerA := OutcomeEdge.fromValue? a | throw (IO.userError "missing fixture owner")
  let some ownerB := OutcomeEdge.fromValue? b | throw (IO.userError "missing fixture owner")
  let all ← IO.ofExcept (Plugin.relation? .all [.semantic ownerA.work,.semantic ownerB.work])
  let source ← publish initial [a,b,plain,all]
  check ((← openShared? source).isNone) "cold read constructed a domain"
  check (!(← (source.directory / "derived").pathExists)) "cold read created source files"
  let sourceHead := source.head
  let sourceBytes ← IO.FS.readBinFile (DB.PageMap.dataPath source.directory source.head)
  let expected ← searchDocuments source
  let built ← refresh source .database
  check (built.mode == "prepared" && built.metadata.stamp.change > 0) "source change was not stamped"
  check ((← DB.PageMap.pin source.directory).head == sourceHead &&
    (← IO.FS.readBinFile (DB.PageMap.dataPath source.directory source.head)) == sourceBytes) "derived preparation changed source DB"
  let source ← DB.PageMap.pin source.directory
  source.trace.set (some {})
  let some prepared ← openShared? source | throw (IO.userError "prepared domain missing")
  let trace ← source.trace.get
  check (trace.any fun trace => trace.complete && trace.operations.all (fun operation => match operation with
    | .point key _ => ["sourceChange","roots","candidates"].contains key
    | _ => false)) "prepared open read owner directories or original bodies"
  check (summary prepared.documents == summary expected) "candidate order/windows changed"
  let reader ← NodeReader.new source
  for row in prepared.data.rows do
    let origin ← reader.workOrigin (← reader.locateOutcome row.owner)
    check (row.origin.work == origin.work && row.origin.native == origin.native &&
      row.ordinal == (← getNat source.get (key "member" row.owner))) "cached Work/native view changed"
  let mut originalLinks := []
  for entry in ← allHeaders source do
    originalLinks := originalLinks ++ [(entry.2.header.parent,entry.2.header.children)]
  check (prepared.data.links == originalLinks) "candidate topology changed"
  let again ← refresh source .database
  check (again.mode == "warm" && again.metadata.digest == built.metadata.digest) "unchanged warm rebuilt domain"
  let mut current := source
  for index in [:20] do
    let _ ← DB.PageMap.withWriter current fun writer => do
      writer.put ("memo:domain-test:" ++ toString index) (some "derived".toUTF8)
      writeChange writer ⟨[],[],false⟩
    current ← DB.PageMap.pin current.directory
  let some afterMemos ← openShared? current | throw (IO.userError "memo-only publication invalidated source domain")
  check (afterMemos.metadata.digest == built.metadata.digest && (← stamp current) == (← stamp source))
    "derived commits advanced source marker"
  let appended ← publish current [native "three"]
  check ((← openShared? appended).isNone && (← stamp appended).change > (← stamp current).change)
    "new graph reused a stale domain"
  let _ ← refresh appended .database
  let some newDomain ← openShared? appended | throw (IO.userError "new publication domain missing")
  let some id ← findNode? appended b | throw (IO.userError "missing retired owner")
  let _ ← DB.PageMap.withWriter appended fun writer => do
    removeRoot writer id
    writeChange writer ⟨[],[id],false⟩
  let retracted ← DB.PageMap.pin appended.directory
  check ((← openShared? retracted).isNone) "retraction retained a ready domain"
  let _ ← refresh retracted .database
  let some retained ← openShared? retracted | throw (IO.userError "retracted domain missing")
  check (retained.data.rows.length+1 == newDomain.data.rows.length && !retained.owners.contains id)
    "retired owner remained in candidate domain"
  let folder ← directory retracted .database
  let good ← IO.FS.readBinFile (folder / "domain")
  FileSystem.atomicExistingBytes (folder / "domain") (good ++ "damage".toUTF8)
  check ((← openShared? retracted).isNone) "corrupt packed domain was accepted"
  let repaired ← refresh retracted .database
  check (repaired.mode == "prepared" && (← openShared? retracted).isSome) "explicit warm did not repair damaged cache"
  let copied := root / "copied.egg"
  IO.FS.createDir copied
  IO.FS.writeBinFile (copied / "head") (← IO.FS.readBinFile (retracted.directory / "head"))
  let copiedPages := DB.PageMap.dataPath copied retracted.head
  IO.FS.writeBinFile copiedPages (← IO.FS.readBinFile (DB.PageMap.dataPath retracted.directory retracted.head))
  for path in [copied / "head",copiedPages] do
    IO.setAccessRights path {user := {read := true},group := {},other := {}}
  IO.setAccessRights copied {user := {read := true,execution := true},group := {},other := {}}
  let beforeHead ← IO.FS.readBinFile (copied / "head")
  let beforePages ← IO.FS.readBinFile copiedPages
  let readOnly ← DB.PageMap.pin copied
  check ((← openShared? readOnly).isNone) "DB-only copy inherited a hidden sidecar"
  let privateDomain ← refresh readOnly .user
  let some portable ← openShared? readOnly | throw (IO.userError "private read-only domain missing")
  check (summary portable.documents == summary retained.documents &&
    privateDomain.metadata.digest == retained.metadata.digest && !(← (copied / "derived").pathExists) &&
    (← IO.FS.readBinFile (copied / "head")) == beforeHead &&
    (← IO.FS.readBinFile copiedPages) == beforePages) "read-only private preparation changed source/order"
  IO.FS.writeFile (root / "domain.json") (Json.mkObj [
    ("rows",toJson retained.data.rows.length),("bytes",toJson retained.metadata.bytes),
    ("windows",toJson retained.metadata.windows),("sourceMarker",toJson retained.metadata.stamp.change),
    ("memoPublications",toJson (20 : Nat)),("portableDigest",toJson portable.metadata.digest),
    ("openSourceObservations",toJson ((trace.map (·.operations.length)).getD 0))]).pretty
  IO.println "candidate domain checks passed: ordered original Work/native/windows/topology, no catalogue/body reads on open, memo stability, append/retract, corruption, explicit repair and DB-only read-only private reconstruction"

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "CandidateDomainTests NEW-DIRECTORY")
  let root := System.FilePath.mk path
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute test directory required")
  IO.FS.createDirAll root
  scenario root
