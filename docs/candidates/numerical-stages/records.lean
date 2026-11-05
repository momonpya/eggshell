import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def destination := workspace/"docs/candidates/numerical-stages"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def array (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def number (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def run (path : System.FilePath) (args : Array String) : IO Unit := do
  let reply ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-j1","-M1536","--run",path.toString]++args,cwd := some workspace}
  IO.print reply.stdout
  IO.eprint reply.stderr
  check (reply.exitCode == 0) "numerical stage helper failed"
def analyze (output : System.FilePath := destination) : IO Unit := do
  let evidence := array (← read (output/"evidence.json")) "runs"
  let mut profiles := #[]
  let mut summaries := #[]
  let mut memory := #[]
  for trial in evidence do
    let tag ← IO.ofExcept (trial.getObjValAs? String "tag")
    let root := base/(tag++"-result")
    let waves := (array trial "waves").filter (fun wave => wave.getObjValD "name" != toJson "prime")
    if waves.isEmpty then continue
    let full ← read (root/"report.json")
    for wave in #[full.getObjValD "first",full.getObjValD "second"] do
      if wave == Json.null then continue
      let mut peak := 0
      let mut peakProcesses := #[]
      for point in array wave "timeline" do
        let pair ← IO.ofExcept point.getArr?
        check (pair.size == 2) "invalid RSS sample"
        let processes ← IO.ofExcept pair[1]!.getArr?
        let total := processes.foldl (fun total process => total+number process "rssKiB") 0
        if peak < total then peak := total; peakProcesses := processes
      memory := memory.push (Json.mkObj [("tag",toJson tag),("wave",wave.getObjValD "name"),
        ("sampledPeakEngineDescendantsRssKiB",toJson peak),("atPeak",toJson peakProcesses),
        ("notAllocationSiteAttribution",toJson true),("excludesControllerAndGuard",toJson true)])
    let mut spans : Array (String × Nat) := #[]
    let mut replies := 0
    let mut profileCount := 0
    let mut drops := 0
    for wave in waves do
      for receipt in array wave "receipts" do
        let id ← IO.ofExcept (receipt.getObjValAs? String "receipt")
        for file in ← (root/"private/receipts"/id).readDir do
          if !file.fileName.startsWith "numerical-" || !file.fileName.endsWith ".json" then continue
          let metric := (← read file.path).getObjValD "data"
          profiles := profiles.push (Json.mkObj [("tag",toJson tag),("receipt",toJson id),
            ("session",receipt.getObjValD "session"),("metric",metric)])
          profileCount := profileCount+1
          let counters := metric.getObjValD "counters"
          drops := drops+number counters "numericalReplyDrops"
          for metadata in array counters "numericalReplies" do
            replies := replies+1
            let events ← IO.ofExcept (fromJson? (metadata.getObjValD "events") : Except String (Array (String × Nat)))
            check (!events.isEmpty && events[0]!.1 == "accepted") "RPC trace omitted accept"
            for i in [1:events.size] do check (events[i-1]!.2 ≤ events[i]!.2) "server clock regressed"
            let started := number metadata "clientStartedAt"
            let received := number metadata "clientReceivedAt"
            let some ready := events.find? (fun event => event.1 == "output-ready") | throw (IO.userError "RPC omitted ready")
            check (started ≤ events[0]!.2 && ready.2 ≤ received) "cross-process clock/order mismatch"
            spans := spans.push ("client-roundtrip",received-started) |>.push ("client-to-accept",events[0]!.2-started)
              |>.push ("ready-to-client",received-ready.2)
            for (name,first,last) in [
                ("accept-to-handler","accepted","handler:start"),("frame-read","request-read:start","request-read:end"),
                ("request-parse","request-parse:start","request-parse:end"),
                ("encode-admission","encode-admission:start","encode-admission:end"),
                ("encode-kernel","encode-kernel:start","encode-kernel:end"),
                ("score-admission","score-admission:start","score-admission:end"),
                ("score-prepare","score-prepare:start","score-prepare:end"),
                ("score-kernel","score-kernel:start","score-kernel:end"),
                ("pipe-write","raw-pipe-write:start","raw-pipe-write:end"),
                ("pipe-read","raw-line-read:start","raw-line-read:end"),
                ("poll-after-read","raw-line-read:end","raw-pipe-task-ready")] do
              if let some a := events.find? (fun event => event.1 == first) then
                let some b := events.find? (fun event => event.1 == last) | throw (IO.userError "completed reply omitted span end")
                check (a.2 ≤ b.2) "RPC span regressed"
                spans := spans.push (name,b.2-a.2)
    let names := spans.toList.map (·.1) |>.eraseDups |>.toArray
    summaries := summaries.push (Json.mkObj [("tag",toJson tag),("profiles",toJson profileCount),
      ("returnedRpcTraces",toJson replies),("replyDrops",toJson drops),
      ("spans",toJson (names.map fun name => Json.mkObj [("stage",toJson name),
        ("wallMs",distribution (spans.filterMap fun (stage,ms) => if stage == name then some ms else none))]))])
  IO.FS.writeFile (output/"memory.json") (toJson memory).pretty
  IO.FS.writeFile (output/"rpc-profiles.json") (Json.mkObj [("profiles",toJson profiles),
    ("runs",toJson summaries),("failedCurrentRpcsUnmeasured",toJson true),
    ("wallTimeNotCpuTime",toJson true),("nestedAndOverlappingSpansNotAdditive",toJson true),
    ("adopted",toJson false)]).pretty
def main (args : List String) : IO Unit := do
  let waits := args.head? == some "--waits"
  let args := if waits then args.drop 1 else args
  let study := if waits then "numerical-waits" else "numerical-stages"
  let output := workspace/"docs/candidates"/study
  if args == ["analyze"] then return ← analyze output
  check (args == ["collect"]) "record mode required"
  let mut tags := if waits then #["--numerical-waits","numerical-waits-build1","numerical-waits-build2","numerical-waits-checks-build1",
    "numerical-waits-checks-build2","numerical-waits-checks-build3","numerical-waits-checks1","numerical-waits-checks2",
    "numerical-waits-off16-1","numerical-waits-on16-1"] else
    #["--numerical-stages","numerical-stages-build1","numerical-stages-build3","numerical-stages-build4",
    "numerical-stages-client-build1","numerical-stages-parent16-1","numerical-stages-off16-1","numerical-stages-on16-1"]
  let has32 ← (base/(study++"-on32-1.guard.json")).pathExists
  if has32 then tags := tags.push (study++"-on32-1")
  let has80 ← (base/(study++"-on80-1.guard.json")).pathExists
  if has80 then tags := tags.push (study++"-on80-1")
  run (workspace/"docs/candidates/shared-leases/records.lean") tags
  let expected := (if waits then 70 else 105)+(if has32 then 35 else 0)+(if has80 then 83 else 0)
  run (workspace/"docs/candidates/shared-leases/records.lean") #["--"++study,"verify",toString expected]
  analyze output
  if waits then
    IO.FS.writeFile (output/"checks.json") (Json.mkObj [
      ("readiness",← read (base/"numerical-waits-checks2-result/report.json")),
      ("waits",← read (base/"numerical-waits-checks2-result/waits.json")),
      ("finalGuard",← read (base/"numerical-waits-checks2.guard.json")),
      ("initialFailedGuard",← read (base/"numerical-waits-checks1.guard.json"))]).pretty
  run (workspace/"tools/research/CaptureConcurrentPatches.lean") #[study]
