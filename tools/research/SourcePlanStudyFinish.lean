import tools.research.StudyLocal
open Lean StudyLocal
namespace SourcePlanStudyFinish
def parent := base/"practical-runtime/source-snapshot"
def roots := #[base/"practical-runtime/producer-window-isolation",base/"practical-runtime/source-plan-contract"]
def records := #[project/"docs/candidates/producer-window-isolation",project/"docs/candidates/source-plan-contract"]
def guardPrefixes := ["producer-window-isolation-","source-plan-contract-","source-plan-context-","source-plan-coordinate-","source-plan-signal-","source-plan-original-"]
def sealOriginals : IO Unit := do
  idle
  discard <| finished "source-plan-signal-diagnostic"
  let mut refused := #[]
  for tag in ["source-plan-original-seal","source-plan-original-checked-seal"] do
    let rejected ← read (base/(tag++".guard.json"))
    check (rejected.getObjValD "state" == toJson "finished" && rejected.getObjValD "exitCode" == toJson (1 : Nat) &&
      rejected.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped inspector setup"
    refused := refused.push rejected
  write (records[1]!/"original-seal-refusal.json") (Json.mkObj [("guards",toJson refused),
    ("errors",toJson #["product entrypoint exposes egg commands, not study artifacts",
      "captured read-only source has no publisher.guard; use its own pre-query frozen file inventory"]),
    ("correction",toJson "compiled native inspector over each original's actual frozen file set"),
    ("originalSourceChanged",toJson false)])
  let plan ← read (roots[1]!/"llvm-plan.json")
  let original ← IO.ofExcept (plan.getObjValAs? String "original")
  let files : Array (String × String) ← IO.ofExcept (fromJson? (plan.getObjValD "originalFiles"))
  let captured := roots[0]!/"llvm/llvm.egg/owners/0/source.egg"
  let frozen ← read (records[1]!/"llvm/before-delivery.json")
  let topics : Array Json ← IO.ofExcept (frozen.getObjValAs? _ "topics")
  let copied : Array (String × String) ← IO.ofExcept ((topics[0]!.getObjValD "specification").getObjValAs? _ "files")
  let expected := files.map (fun (name,digest) => (original++"/"++name,digest))++
    copied.map (fun (name,digest) => ((captured/name).toString,digest))
  write (records[1]!/"expected-originals.json") (toJson expected)
  guard "source-plan-original-native-seal" (#["/bin/sh","-c",
    "captured_output=$1; shift; exec \"$@\" >\"$captured_output\"","source-original-seal",
    (records[1]!/"originals-verified.json").toString,
    (base/"practical-runtime/build/StudyMain").toString,"artifacts"]++expected.map Prod.fst)

def collect : IO Unit := do
  idle
  discard <| finished "source-plan-original-native-seal"
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (records[1]!/"expected-originals.json")))
  let sealed : Array Json ← IO.ofExcept ((← read (records[1]!/"originals-verified.json")).getArr?)
  check (!expected.isEmpty && sealed.size == expected.size) "original fingerprint census changed"
  for (path,digest) in expected do
    check (sealed.any fun row => row.getObjValD "path" == toJson path && row.getObjValD "sha256" == toJson digest)
      "native post-study original fingerprint differs"
  let mut stages := #[]
  for entry in ← base.readDir do
    if entry.fileName.endsWith ".guard.json" && guardPrefixes.any (fun prefixName => entry.fileName.startsWith prefixName) then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "study still owns live work"
      stages := stages.push (entry.fileName,value)
  stages := stages.qsort fun a b => a.1 < b.1
  write (records[1]!/"guards.json") (toJson stages)
  for index in [:roots.size] do
    let root := roots[index]!
    let destination := records[index]!
    let result ← read (destination/"llvm/result.json")
    let queries : Array Json ← IO.ofExcept (result.getObjValAs? _ "queries")
    check (queries.size == 6 && result.getObjValD "answeringModelCalls" == toJson (0 : Nat) &&
      result.getObjValD "adopted" == toJson false) "unexpected model or adoption state"
    let mut bodies : Array (String × String) := #[]
    let mut references := #[]
    for query in queries do
      let pass ← IO.ofExcept (query.getObjValAs? Nat "pass")
      let topic ← IO.ofExcept (query.getObjValAs? Nat "topic")
      let path := destination/"llvm"/s!"pass-{pass}-topic-{topic}.txt"
      let body ← IO.FS.readFile path
      let digest ← hash path
      check (toJson digest == query.getObjValD "bodySha256" &&
        toJson body.utf8ByteSize == query.getObjValD "bodyBytes") "actual saved body differs from native callback audit"
      match bodies.find? (·.1 == digest) with
      | some prior => check (prior.2 == body) "body digest aliases differ"
      | none => bodies := bodies.push (digest,body)
      references := references.push (pass,topic,digest)
    write (destination/"llvm/bodies.json") (Json.mkObj [("bodies",toJson bodies),("references",toJson references)])
    let roundtrip : Array (String × String) ← IO.ofExcept ((← read (destination/"llvm/bodies.json")).getObjValAs? _ "bodies")
    check (roundtrip == bodies) "lossless body serialization differs"
    let mut calls := #[]
    for session in ← (root/"llvm/calls").readDir do
      for call in ← session.path.readDir do
        if !(← (call.path/"record.json").pathExists) then continue
        calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
          ("record",← read (call.path/"record.json")),("input",toJson (← IO.FS.readFile (call.path/"stdin"))),
          ("stdout",toJson (← IO.FS.readFile (call.path/"stdout"))),
          ("stderr",toJson (← IO.FS.readFile (call.path/"stderr")))])
    check (calls.size == 18) "registered callback census differs"
    write (destination/"llvm/callbacks.json") (toJson calls)
    let mut stops := #[]
    for name in ["host","client-publisher","frontend"] do
      let report ← read (destination/"llvm"/(name++"-stop.json"))
      check (report.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
        report.getObjValD "acknowledged" == toJson true && report.getObjValD "processExited" == toJson true &&
        report.getObjValD "endpointRemoved" == toJson true && report.getObjValD "phase" == toJson "stopped")
        "registered service was not stopped normally"
      stops := stops.push (name,report)
    write (destination/"llvm/stops.json") (toJson stops)
  for kind in ["ProducerWindowAudit","SourcePlanContractAudit"] do
    let stem := "tools_research_"++kind
    let stdout ← IO.FS.readFile (roots[1]!/"llvm-build"/(stem++"-lean.stdout"))
    let stderr ← IO.FS.readFile (roots[1]!/"llvm-build"/(stem++"-lean.stderr"))
    check (stderr.isEmpty && !stdout.contains "error:" && !stdout.contains "sorryAx" &&
      !stdout.contains "Lean.trustCompiler" && !stdout.contains "Lean.ofReduceBool") "kernel law audit failed"
    write (records[1]!/(kind++".json")) (Json.mkObj [("stdout",toJson stdout),("stderr",toJson stderr),
      ("executedSource",← read (roots[1]!/"llvm-build"/(stem++".source"))),
      ("standardAxiomsOnly",toJson true)])
  write (records[1]!/"coordinate-executed-source.json")
    (← read (roots[1]!/"witness-build/tools_research_ProducerPlanProbe.source"))
  write (records[1]!/"signal-audit-refusal.json") (Json.mkObj [
    ("error",toJson "SelectorSignalAudit.lean:64:62: failed to synthesize ToJson Prop"),
    ("correction",toJson "decide the proposition before encoding its Boolean"),
    ("productChanged",toJson false),("queryOrModelCalled",toJson false)])

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    total := (total.1+counts.1,total.2+counts.2)
  IO.FS.removeDir path
  return total

def retire : IO Unit := do
  idle
  let inputs : Array (String × String) ← IO.ofExcept
    (fromJson? (← read (project/"docs/candidates/source-snapshot/protected-native-inputs.json")))
  check (inputs.size == 355) "protected current native input set changed"
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "protected native input changed before retirement"
  check (roots.all fun root => !(inputs.any fun (path,_) => path.startsWith (root.toString++"/")))
    "rejected study owns a protected native input"
  check ((← read (records[1]!/"llvm/result.json")).getObjValD "allSixReachTarget" == toJson false)
    "retire only this rejected study"
  check (← (records[1]!/"guards.json").pathExists) "compact terminal evidence is missing"
  let mut total := (0,0)
  for root in roots do
    let counts ← remove root
    total := (total.1+counts.1,total.2+counts.2)
  for destination in records do
    for pass in [:2] do
      for topic in [1,2,3] do
        discard <| remove (destination/"llvm"/s!"pass-{pass}-topic-{topic}.txt")
    for name in ["host","client-publisher","frontend"] do
      discard <| remove (destination/"llvm"/(name++"-stop.json"))
  for relative in ["llvm/diagnostic/body.txt","signals/diagnostic/body.txt","signals/pass-0-topic-1.txt",
    "signals/before-delivery.json","signals/audit.json"] do
    discard <| remove (records[1]!/relative)
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "protected native input changed after retirement"
  write (records[1]!/"retired.json") (Json.mkObj [("removedRoots",toJson (roots.map (·.toString))),
    ("files",toJson total.1),("logicalBytes",toJson total.2),("archived",toJson false),
    ("protectedNativeInputs",toJson inputs.size),("allProtectedHashesUnchanged",toJson true),
    ("bodyTextRetainedLosslessly",toJson true),("currentParent",toJson parent.toString),
    ("adopted",toJson false)])
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(parent/"build").toString,
    (records[1]!/"parent-after-retirement.json").toString]

/-- Keep reviewable JSON evidence, not dozens of loose files or DB archives.
Round-trip every value before removing its redundant standalone copy. -/
def pack (directory : System.FilePath) (output : String) (names : Array String) : IO Unit := do
  check (!(← (directory/output).pathExists)) "preserve compact study evidence"
  let mut entries := #[]
  for name in names do entries := entries.push (name,← read (directory/name))
  let value := Json.mkObj entries.toList
  write (directory/output) value
  check ((← read (directory/output)) == value) "compact JSON evidence changed a value"
  for name in names do discard <| remove (directory/name)

partial def names (directory : System.FilePath) (start : String := "") : IO (Array String) := do
  let mut result := #[]
  for entry in ← (directory/start).readDir do
    let relative := if start.isEmpty then entry.fileName else start++"/"++entry.fileName
    if (← entry.path.symlinkMetadata).type == .dir then result := result++(← names directory relative)
    else if entry.fileName.endsWith ".json" then result := result.push relative
  return result

def compact : IO Unit := do
  idle
  check ((← read (records[1]!/"parent-after-retirement.json")).getObjValD "consistent" == toJson true)
    "retirement did not preserve the fixed parent"
  for directory in records do
    let result ← read (directory/"llvm/result.json")
    check ((← read (directory/"llvm/queries.json")) == result.getObjValD "queries")
      "query log differs from retained result"
    discard <| remove (directory/"llvm/queries.json")
    let entries := (← names directory).qsort (· < ·)
    let diagnostic := entries.filter fun name => name.startsWith "llvm/diagnostic/" || name.startsWith "signals/" ||
      name.startsWith "context-" || name.startsWith "coordinate-"
    let llvm := entries.filter fun name => name.startsWith "llvm/" && !diagnostic.contains name
    let validation := entries.filter fun name => !diagnostic.contains name && !llvm.contains name &&
      !["plan.json","harness.json","retired.json"].contains name
    if !diagnostic.isEmpty then pack directory "diagnostics.json" diagnostic
    pack directory "llvm.json" llvm
    pack directory "validation.json" validation
    for name in ["llvm","signals"] do
      if ← (directory/name).pathExists then discard <| remove (directory/name)
end SourcePlanStudyFinish
def main : List String → IO Unit
  | ["seal"] => SourcePlanStudyFinish.sealOriginals
  | ["collect"] => SourcePlanStudyFinish.collect
  | ["retire"] => SourcePlanStudyFinish.retire
  | ["compact"] => SourcePlanStudyFinish.compact
  | _ => throw (IO.userError "SourcePlanStudyFinish seal|collect|retire")
