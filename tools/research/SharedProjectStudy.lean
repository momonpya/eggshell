import tools.research.StudyLocal
open Lean StudyLocal
namespace SharedProjectStudy

def practical := base/"practical-runtime"
def candidate := practical/"coordinated-warm"
def records := project/"docs/practical-runtime/shared-project"
def proofs := project/"docs/candidates/coordinated-warm"

/-- Retain proof/byte evidence only. DB operations run exclusively in the
compiled SharedProjectLifecycle controller and native product. -/
def confirmProof : IO Unit := do
  idle
  let proof ← finished "practical-coordinated-warm-proof"
  let result ← read (records/"fresh-lifecycle/result.json")
  check ((result.getObjValD "runtime").getObjValD "sha256" == toJson (← hash (candidate/"build/StudyMain")))
    "tested candidate changed"
  let manifest ← read (proofs/"patch-check.json")
  check (manifest.getObjValD "patchSha256" == toJson (← hash (proofs/"candidate.patch"))) "tested patch changed"
  for row in ← IO.ofExcept (manifest.getObjValAs? (Array Json) "sources") do
    let path ← IO.ofExcept (row.getObjValAs? String "path")
    check (row.getObjValD "sha256" == toJson (← hash (candidate/"source"/path))) "native source changed"
  write (proofs/"proof.json") (Json.mkObj [("guard",proof),("kernelAndConsumerAuditPassed",toJson true),
    ("additionalAxioms",toJson #["propext","Quot.sound"]),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)])

partial def files (root : System.FilePath) : IO (Array System.FilePath) := do
  let mut result := #[]
  for entry in ← root.readDir do
    if (← entry.path.symlinkMetadata).type == .dir then result := result ++ (← files entry.path)
    else result := result.push entry.path
  return result

def inside (path root : System.FilePath) : Bool :=
  path == root || path.toString.startsWith (root.toString++"/")

def tidyRecords : IO Unit := do
  idle
  for name in ["same-snapshot","read-only-probe","fresh-lifecycle"] do
    let folder := records/name
    let mut audit := []
    let mut paths := #[]
    for entry in ← folder.readDir do
      if entry.fileName == "result.json" || !entry.fileName.endsWith ".json" then continue
      audit := audit ++ [(entry.fileName,← read entry.path)]
      paths := paths.push entry.path
    let result ← read (folder/"result.json")
    check (!(result.getObjVal? "audit").isOk) "preserve existing combined audit"
    write (folder/"result.json") (result.setObjVal! "audit" (Json.mkObj audit))
    for path in paths do IO.FS.removeFile path
  let mut failures := []
  let mut paths := #[]
  for entry in ← records.readDir do
    if !(entry.fileName.startsWith "rejected-" || entry.fileName.startsWith "readiness") then continue
    failures := failures ++ [(entry.fileName,← read entry.path)]
    paths := paths.push entry.path
  write (records/"failures.json") (Json.mkObj failures)
  for path in paths do IO.FS.removeFile path

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      total := (total.1+part.1,total.2+part.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if info.type == .file then info.byteSize.toNat else 0)

def cleanup : IO Unit := do
  idle
  discard <| finished "practical-coordinated-warm-owner-lifecycle"
  discard <| finished "practical-coordinated-warm-proof"
  check (!(← (records/"retired.json").pathExists)) "preserve previous cleanup receipt"
  for name in ["same-snapshot","read-only-probe","fresh-lifecycle"] do
    let result ← read (records/name/"result.json")
    let rows ← IO.ofExcept (result.getObjValAs? (Array Json) "delivery")
    check (rows.size == 2 && rows.all (fun row => row.getObjValD "delivered" == toJson (10 : Nat)))
      "retain successful bodies before deleting fixture data"
    for index in [:2] do
      check (rows[index]!.getObjValD "sha256" == toJson (← hash (records/name/s!"reader-{index}/body.txt")))
        "retained delivered body changed"
  let targets := #[practical/"shared-project/run",candidate/"run",candidate/"reader-repair",
    candidate/"fresh",candidate/"fresh-final",candidate/"fresh-shared",candidate/"read-only-probe",
    candidate/"owner-lifecycle"]
  let mut preserved := #[base/"canonical-decoder-runtime/build/StudyMain",practical/"build/StudyMain",
    candidate/"build/StudyMain",practical/"package/prefix/libexec/eggshell"]
  preserved := preserved ++ (← files (practical/"cohort/study/seed-1/work.egg"))
  let hashes ← preserved.mapM fun path => do pure (path,← hash path)
  for build in [base/"canonical-decoder-runtime/build",practical/"build",candidate/"build"] do
    for line in (← IO.FS.readFile (build/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let input : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if !input.isAbsolute then continue
      check (!(targets.any (inside (← IO.FS.realPath input)))) "live native input belongs to an ended fixture"
  let processes ← command "/bin/ps" #["-axo","command="]
  for path in targets do
    check ((processes.splitOn path.toString).length == 1) "fixture still has a live process"
  let mut deleted := #[]
  let mut total := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let counts ← remove path
    total := (total.1+counts.1,total.2+counts.2)
    deleted := deleted.push (path.toString,counts.1,counts.2)
  for (path,expected) in hashes do check ((← hash path) == expected) "protected original/runtime changed"
  write (records/"retired.json") (Json.mkObj [("deleted",toJson deleted),("files",toJson total.1),
    ("logicalBytes",toJson total.2),("archiveCreated",toJson false),
    ("protectedHashesBeforeAndAfter",toJson true),("protectedFiles",toJson hashes.size),
    ("liveNativeInputsOutsideDeletedFixtures",toJson true)])

def main : List String → IO Unit
  | ["seal"] => confirmProof
  | ["cleanup"] => cleanup
  | ["tidy-records"] => tidyRecords
  | _ => IO.println "SharedProjectStudy seal | cleanup | tidy-records"
end SharedProjectStudy
def main := SharedProjectStudy.main
