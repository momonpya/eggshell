import tools.research.StudyLocal
open Lean StudyLocal

def evidence := project/"docs/candidates/request-lifetime"
def arr (value : Json) (key : String) : Array Json :=
  (value.getObjValAs? (Array Json) key).toOption.getD #[]
def nat (value : Json) (key : String) : Nat :=
  (value.getObjValAs? Nat key).toOption.getD 0

partial def reduced (value : Json) : Json :=
  match value with
  | .arr values => Json.mkObj [("arrayEntries",toJson values.size)]
  | .obj fields => Json.mkObj (fields.toArray.toList.map fun (key,value) =>
      (key,if key == "queryStages" || key == "unverifiedParts" then value else reduced value))
  | _ => value

partial def sizeOfPath (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut result := (0,0)
  for entry in ← path.readDir do
    let part ← sizeOfPath entry.path
    result := (result.1+part.1,result.2+part.2)
  return result

partial def erase (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do erase entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def validId (value : String) : Bool := !value.isEmpty && value.toList.all fun c => c.isAlphanum || c == '-'

def main : IO Unit := do
  idle
  let observation ← read (evidence/"observation.json")
  let summary ← read (evidence/"summary.json")
  let guardRecord := observation.getObjValD "guard"
  check (guardRecord.getObjValD "state" == toJson "finished" &&
    guardRecord.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "execution has not drained"
  check (!(← (evidence/"cleanup.json").pathExists)) "cleanup already recorded"
  let profiles ← IO.ofExcept ((← read (evidence/"service-profiles.json")).getArr?)
  let publisher := nat summary "publisherPid"
  let data := base/"prepared-literals-fixture/data"
  let live ← command "/bin/ps" #["-axo","command="]
  for name in ["byte-pages-prefix/libexec/eggshell","request-timeline-build/StudyMain"] do
    check (!(live.contains (base/name).toString)) "study runtime is still live"
  let mut paths : Array System.FilePath := #[]
  let mut sessionRecords := #[]
  for client in arr observation "clients" do
    let session ← IO.ofExcept (client.getObjValAs? String "session")
    let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
    check (validId session && validId receipt) "invalid ended study identifier"
    let directory := data/"sessions"/session
    let state ← read (directory/"state.json")
    let reference := state.getObjValD "confirmedDelivery"
    let authority ← IO.ofExcept (reference.getObjValD "head" |>.getObjValAs? String "authority")
    check (authority.startsWith "confirmed-delivery:") "foreign delivery authority"
    let context := (authority.drop 19).toString
    check (context.length == 64 && context.toList.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')) "invalid delivery context"
    let ledger := data/"confirmed-delivery"/context
    let head ← read (ledger/"head")
    check (head.getObjValD "identity" == (reference.getObjValD "head").getObjValD "identity") "delivery identity mismatch"
    paths := paths ++ #[directory,data/"receipts"/receipt,ledger]
    sessionRecords := sessionRecords.push (Json.mkObj [("session",toJson session),("receipt",toJson receipt),
      ("ledgerIdentity",head.getObjValD "identity")])
  let mut seenProfiles : Std.HashSet String := {}
  for profile in profiles do
    let id ← IO.ofExcept (profile.getObjValAs? String "receiptDirectory")
    if seenProfiles.contains id then continue
    check (validId id && nat profile "pid" == publisher) "foreign service profile"
    seenProfiles := seenProfiles.insert id
    let directory := data/"receipts"/id
    for entry in ← directory.readDir do
      check (entry.fileName.endsWith ".json") "unidentified service profile file"
      let record ← read entry.path
      check (nat record "pid" == publisher &&
        profiles.any (fun known => known.getObjValD "receiptDirectory" == toJson id &&
          known.getObjValD "observedMs" == record.getObjValD "observedMs" &&
          known.getObjValD "stage" == record.getObjValD "stage")) "service profile is outside the captured trial"
    paths := paths.push directory
  for (name,expected) in [("publisher/endpoint.json",publisher),("daemon.json",98380)] do
    let path := data/name
    let endpoint ← read path
    check (nat endpoint "pid" == expected) "endpoint belongs to a different run"
    let result ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString expected,"-o","pid="]}
    check (result.exitCode == 1 && result.stdout.trimAscii.toString.isEmpty) "recorded endpoint PID still exists"
    paths := paths.push path
  let removedBuild := base/"request-timeline-build"
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if entry.path != removedBuild && (← response.pathExists) then
      check (!(← IO.FS.readFile response).contains (removedBuild.toString++"/")) "another build needs diagnostic objects"
  for name in ["request-timeline-build","request-timeline-source","request-timeline-result",
    "request-timeline-samples.jsonl","request-timeline-input.json","request-timeline-settings.json",
    "request-timeline-closure.json","request-timeline-sources.json","request-timeline-control.lean",
    "request-timeline-analysis.lean","request-timeline-summarize.lean"] do paths := paths.push (base/name)
  for tag in ["request-timeline-build1","request-timeline-build2","request-timeline-run1"] do
    for suffix in [".guard.json",".guard-settings.json",".stdout",".stderr"] do paths := paths.push (base/(tag++suffix))
  let protectedPaths ← IO.ofExcept ((← read (project/"docs/candidates/prepared-read-evidence/cleanup.json")).getObjValAs?
    (Array (String × String)) "protectedHashesBeforeAndAfter")
  for (name,digest) in protectedPaths do check ((← hash (.mk name)) == digest) "protected input changed before cleanup"
  let root ← IO.FS.realPath base
  let mut removed := #[]
  let mut total := (0,0)
  let mut unique : Std.HashSet String := {}
  for path in paths do
    if unique.contains path.toString || !(← path.pathExists) then continue
    unique := unique.insert path.toString
    let parent ← IO.FS.realPath path.parent.get!
    check (parent == root || parent.toString.startsWith (root.toString++"/")) "cleanup escaped study root"
    check (!(live.contains path.toString)) "ended artifact is live"
    let size ← sizeOfPath path
    removed := removed.push (path.toString,size)
    total := (total.1+size.1,total.2+size.2)
  let reducedStages := (arr observation "stages").map fun row =>
    let record := row.getObjValD "record"
    Json.mkObj [("receipt",row.getObjValD "receipt"),("phase",row.getObjValD "phase"),
      ("topic",row.getObjValD "topic"),("name",row.getObjValD "name"),
      ("observedMs",record.getObjValD "observedMs"),("pid",record.getObjValD "pid"),
      ("data",reduced (record.getObjValD "data"))]
  write (evidence/"observation.json") (observation.setObjVal! "stages" (toJson reducedStages))
  let cleanupRecord := Json.mkObj [("removed",toJson removed),("removedFiles",toJson total.1),
    ("removedLogicalBytes",toJson total.2),("sessions",toJson sessionRecords),
    ("serviceProfileDirectories",toJson seenProfiles.size),("protectedHashesBeforeAndAfter",toJson protectedPaths),
    ("bothDeadEndpointsVerifiedBeforeUnlink",toJson true),("archiveCreated",toJson false)]
  write (evidence/"cleanup.json") (cleanupRecord.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then erase path
  for (name,digest) in protectedPaths do check ((← hash (.mk name)) == digest) "protected input changed after cleanup"
  write (evidence/"cleanup.json") (cleanupRecord.setObjVal! "completed" (toJson true))
  IO.FS.writeFile (evidence/"Cleanup.lean") (← IO.FS.readFile (base/"request-timeline-finish.lean"))
  IO.println s!"removed {total.1} ended files / {total.2} logical bytes; {protectedPaths.size} protected hashes unchanged"
