import tools.research.StudyLocal
open Lean StudyLocal

def cohort := base/"current-six/fixed-sequence/cohort"
def reports := project/"docs/candidates/stable-source-rows/sequence"
def controller := base/"current-six/fixed-sequence/controller-build/StudyMain"

def main (args : List String) : IO Unit := do
  idle
  let run := cohort/"study/seed-1"
  if args == ["account"] then
    let monitor ← read (cohort/"seed-1.guard.json")
    check (monitor.getObjValD "state" == toJson "finished" &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "seed still owns processes"
    let thread ← read (run/"thread.json")
    let turn ← read (run/"turn-start.json")
    let scope := Json.mkObj [
      ("threadId",(← IO.ofExcept (thread.getObjVal? "thread")).getObjValD "id"),
      ("turnId",(← IO.ofExcept (turn.getObjVal? "turn")).getObjValD "id"),
      ("expectedBodySha256",toJson "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")]
    let scopePath := reports/"disk-stopped-seed-scope.json"
    check (!(← scopePath.pathExists)) "keep the recorded failure"
    write scopePath scope
    discard <| command controller.toString #["replay",scopePath.toString,
      (run/"rpc/exchange.jsonl").toString,(reports/"disk-stopped-seed-usage.json").toString]
    let usage ← read (reports/"disk-stopped-seed-usage.json")
    check (usage.getObjValD "unknownFinalUsage" == toJson true &&
      usage.getObjValD "terminalStatus" == .null) "unexpected terminal state; inspect before retiring"
    write (reports/"disk-stopped-seed-guard.json") monitor
    for name in #["plan.json","limits.json","thread.json","turn-start.json"] do
      write (reports/("disk-stopped-seed-"++name)) (← read (run/name))
    write (reports/"disk-stopped-seed.json") (Json.mkObj [
      ("accepted",toJson false),("reason",toJson "disk-space"),
      ("usage",usage),("finalInclusiveTokens",Json.null),
      ("recoverableChat",toJson false),("ephemeralChat",toJson true),
      ("productFailureObserved",toJson false),("adopted",toJson false)])
  else if args == ["retire"] then
    let receipt ← read (reports/"disk-stopped-seed.json")
    check (receipt.getObjValD "accepted" == toJson false &&
      receipt.getObjValD "reason" == toJson "disk-space") "account for the failed run first"
    let keepers := #[controller,base/"current-six/stable-source-rows/build/StudyMain",
      base/"owned-selection-runtime-build/StudyMain",base/"byte-pages-prefix/libexec/eggshell"]
    let before ← keepers.mapM fun path => return (path.toString,← hash path)
    let mut removed := #[]
    for name in #["compiled-owner-plan-prefix","deferred-audit-prefix","draft-units-prefix",
        "full-fallback-prefix","lexical-graph-prefix","reference-capacity-prefix","reference-records-prefix"] do
      let path := base/name
      if ← path.pathExists then
        IO.FS.removeDirAll path
        removed := removed.push path.toString
    -- Keep the compact RPC/plan receipts. No unfinished DB is an accepted seed.
    for name in #["work.egg","input.egg","data"] do
      let path := run/name
      if ← path.pathExists then
        IO.FS.removeDirAll path
        removed := removed.push path.toString
    let after ← keepers.mapM fun path => return (path.toString,← hash path)
    check (before == after) "selected runtime/controller/comparator changed during retirement"
    write (reports/"capacity-cleanup.json") (Json.mkObj [
      ("removed",toJson removed),("protected",toJson after),("archiveCreated",toJson false),
      ("failedSeedAccepted",toJson false)])
  else if args == ["isolate-hooks"] then
    let failed := cohort/"study/seed-2"
    let failure ← read (failed/"failure.json")
    check (failure.getObjValD "runError" == toJson "unexpected active hook in acquisition")
      "unexpected acquisition failure"
    let monitor ← read (cohort/"seed-2.guard.json")
    check (monitor.getObjValD "state" == toJson "finished" &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "probe still owns processes"
    let mut generationRequests := 0
    for line in (← IO.FS.readFile (failed/"rpc/exchange.jsonl")).splitOn "\n" do
      let .ok row := Json.parse line | continue
      if (row.getObjValD "message").getObjValD "method" == toJson "turn/start" then
        generationRequests := generationRequests+1
    check (generationRequests == 0) "a generation request was sent; retain its cost separately"
    let configuration := cohort/"account/config.toml"
    let before ← hash configuration
    let groups ← IO.ofExcept ((← read (failed/"hooks.json")).getObjValAs? (Array Json) "data")
    let mut additions := ""
    let mut keys : Array String := #[]
    for group in groups do
      for hook in ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks") do
        let id ← IO.ofExcept (hook.getObjValAs? String "pluginId")
        if id == "eggshell@eggshell" then continue
        check (id == "eggshell@openai-curated-remote") "unexpected additional plugin"
        let key ← IO.ofExcept (hook.getObjValAs? String "key")
        check (!(← IO.FS.readFile configuration).contains ("[hooks.state."++(toJson key).compress++"]"))
          "duplicate hook override"
        additions := additions++"\n[hooks.state."++(toJson key).compress++"]\nenabled = false\n"
        keys := keys.push key
    check (keys.size == 7) "expected the seven unselected remote hooks"
    let handle ← IO.FS.Handle.mk configuration .append
    handle.putStr additions
    handle.flush
    write (reports/"duplicate-hook-admission.json") (Json.mkObj [
      ("generationRequests",toJson generationRequests),("accepted",toJson false),
      ("failure",failure),("guard",monitor),("disabledUnselectedHooks",toJson keys),
      ("configurationBeforeSha256",toJson before),("configurationSha256",toJson (← hash configuration)),
      ("scope",toJson "isolated experiment account only"),("productRuntimeChanged",toJson false)])
  else if args == ["probe"] then
    let path := cohort/"discovery-isolated.input.json"
    check (!(← path.pathExists)) "keep earlier discovery"
    write path ((← read (cohort/"discovery.input.json"))
      |>.setObjVal! "output" (toJson (cohort/"discovery-isolated").toString))
    guard "fixed-sequence-isolated-hooks" #[controller.toString,"probe",path.toString]
  else if args == ["persistent-replay"] then
    let acquired := cohort/"study/seed-3"
    check ((← read (acquired/"result.json")).getObjValD "completed" == toJson true)
      "completed durable acquisition required"
    let directory := cohort/"persistent-replay"
    check (!(← directory.pathExists)) "preserve replay evidence"
    IO.FS.createDir directory
    let plan ← read (cohort/"seed-3.plan.json")
    let runtime ← IO.ofExcept ((← IO.ofExcept (plan.getObjVal? "runtime")).getObjValAs? String "path")
    let thread ← read (acquired/"thread.json")
    let session ← IO.ofExcept ((← IO.ofExcept (thread.getObjVal? "thread")).getObjValAs? String "id")
    let request := cohort/"seed-ready/finish-replay/request.json"
    IO.FS.writeFile (directory/"request.json") (← IO.FS.readFile request)
    guard "fixed-sequence-persistent-replay" #["/usr/bin/env",
      "EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
      "EGGSHELL_CONFIG="++(acquired/"config.toml").toString,
      "CODEX_THREAD_ID="++session,"EGGSHELL_PROFILE=work","HF_HUB_OFFLINE=1","LEAN_NUM_THREADS=1",
      "/bin/sh","-c","exec \"$1\" codex-worker index > \"$2\" 2> \"$3\"","eggshell-native-replay",
      runtime,(directory/"stdout.jsonl").toString,(directory/"stderr").toString]
  else throw (IO.userError "account|retire|isolate-hooks|probe|persistent-replay")
