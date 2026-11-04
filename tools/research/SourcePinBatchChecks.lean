import Main
open Lean Eggshell Eggshell.Plugin Eggshell.DB
namespace Eggshell.Research.SourcePinBatchChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def run (source root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier source-pin audit"
  IO.FS.createDirAll root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identity.exitCode == 0) "audit runtime identity missing"
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let expected := (← read (source/"frozen-readback.json")).getObjValD "sourceHeads"
  let snapshots ← (List.range 16).toArray.mapM fun owner => PageMap.pin (source/"work.project/owners"/toString owner/"source.egg")
  check (toJson (snapshots.map (·.head)) == expected) "original cut changed"
  let command ← MiniLM.command (← Paths.installRoot)
  let project := (source/"work.project").toString
  let config := root/"eggshell.toml"
  IO.FS.writeFile config ("default = \"work\"\n[eggs]\nwork = \""++project++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let warm ← IO.Process.output {
    cmd := (← IO.appPath).toString
    args := #["egg","warm",project]
    env := #[("EGGSHELL_CONFIG",some config.toString)]}
  IO.FS.writeFile (root/"warm-stdout.json") warm.stdout
  IO.FS.writeFile (root/"warm-stderr.txt") warm.stderr
  check (warm.exitCode == 0) "source pin audit warm failed"
  let now ← IO.monoMsNow
  let deadline := now+28000
  let openDeadline := deadline-5000
  let receipt ← Receipt.fresh
  let pending ← ProjectContext.capture {
    sessionId := "source-pin-batch",turnId := "turn",cwd := source.toString,
    prompt := "Return the recorded head and tail facts for support case-79.",
    profile := "work",semanticMatcher := command,read := [project],write := some project,
    handoffChars := 120000,projection := .automatic} deadline (some receipt)
  let some encoded := pending.preparedInputs | throw (IO.userError "prepared frame unavailable")
  let frame ← IO.ofExcept (fromJson? (α := PreparedInputs.Frame) encoded.payload)
  check (frame.inputs.size == snapshots.size) "incomplete source inventory"
  let requests ← (snapshots.zip frame.inputs).mapM fun (snapshot,input) => do
    let some (storage,metadata) := input.canonical | throw (IO.userError "canonical source unavailable")
    return ({source := snapshot,storage,captured := metadata} : Publication.Client.SourcePin)
  let mut timings := #[]
  let mut identities : Option (Array Json) := none
  try
    for pair in [0,1,2] do
      for batch in (if pair == 1 then [true,false] else [false,true]) do
        let started ← IO.monoMsNow
        let refs ← if batch then do
            let replies ← Publication.Client.retainSources requests openDeadline deadline
            replies.mapM fun reply => do
              let some reference ← IO.ofExcept reply | throw (IO.userError "batched source unavailable")
              return reference
          else requests.mapM fun request => do
            let some reference ← Publication.Client.retainSourceAt request.source request.storage request.captured openDeadline deadline |
              throw (IO.userError "scalar source unavailable")
            return reference
        let opened ← IO.monoMsNow
        let actual := refs.map (·.identity)
        if let some expected := identities then check (toJson actual == toJson expected) "batch changed source identity or order"
        else identities := some actual
        check (refs.size == 16 && refs.all (·.retained.isSome)) "source pin omitted a retained input"
        if batch then Publication.Client.releaseSources refs deadline
        else for reference in refs do reference.release deadline
        timings := timings.push (Json.mkObj [("pair",toJson pair),("batched",toJson batch),
          ("openMs",toJson (opened-started)),("releaseMs",toJson ((← IO.monoMsNow)-opened)),("sources",toJson refs.size)])
    let endpoint ← Publication.Client.resolve
    let missing ← try
        let _ ← Publication.Client.checkedSourceBatch endpoint requests deadline #[]
        pure false
      catch _ => pure true
    check missing "short reply inventory accepted"
    let oversized ← try
        let _ ← Daemon.exchangeBefore endpoint "prepare-source-batch"
          (Json.mkObj [("budgetMs",toJson (1000 : Nat)),("requests",toJson (Array.replicate 17 Json.null))]) deadline
        pure false
      catch _ => pure true
    check oversized "server accepted oversized source-pin batch"
    let some first := requests[0]? | throw (IO.userError "missing first prepared source")
    let bad := {first with captured := {first.captured with source := {first.captured.source with identity := "wrong-database"}}}
    let replies ← Publication.Client.retainSources (requests.set! 0 bad) openDeadline deadline
    let mut retained := #[]
    for (reply,index) in replies.zipIdx do
      match reply with
      | .ok (some reference) =>
        check (index != 0) "wrong captured manifest acquired a source pin"
        retained := retained.push reference
      | _ => check (index == 0) "bad item prevented another original from being retained"
    check (retained.size == 15) "partial source-pin result lost unaffected inputs"
    let some live := retained[0]? | throw (IO.userError "missing retained source")
    let denied ← Daemon.exchangeBefore endpoint "release-retained-source-batch" (Json.mkObj [
      ("budgetMs",toJson (1000 : Nat)),("requests",toJson #[Json.mkObj [
        ("database",toJson live.access.database),("scope",toJson live.access.scope),
        ("retained",toJson live.retained),("secret",toJson "wrong-capability")]])]) deadline
    check ((← IO.ofExcept (Json.parse denied >>= fromJson? (α := Array Bool))) == #[false]) "batch release bypassed per-source authority"
    let _ ← Publication.Client.sourceRecords live #[] deadline
    Publication.Client.releaseSources retained deadline
    let doubled ← Publication.Client.retainSources (requests++requests) openDeadline deadline
    let doubled ← doubled.mapM fun reply => do
      let some reference ← IO.ofExcept reply | throw (IO.userError "multi-batch source unavailable")
      return reference
    check (doubled.size == 32 && toJson (doubled.map (·.identity)) == toJson ((identities.getD #[])++(identities.getD #[])))
      "transport grouping truncated the configured inventory"
    Publication.Client.releaseSources doubled deadline
    let prepared ← Synapses.Recommend.prepareMany snapshots (some frame.inputs) deadline
    check (toJson (prepared.map (·.source.head)) == expected &&
      prepared.all (fun item => item.failure.isNone && item.canonical.isSome && item.canonicalFailure.isNone))
      "normal preparation changed source order or lost canonical input"
    check (toJson (prepared.map (fun item => item.usage.map (·.index.head))) == toJson (frame.inputs.map (·.usage)))
      "normal preparation changed captured private usage roots"
    Synapses.Recommend.releaseMany prepared deadline
    let after ← Daemon.exchange endpoint "stats" (budget := 1000)
    let status ← IO.ofExcept (Json.parse after)
    let leases := status.getObjValD "retainedSources"
    check (leases.getObjValD "active" == toJson (0 : Nat) && leases.getObjValD "chargedBytes" == toJson (0 : Nat) &&
      leases.getObjValD "readers" == toJson (0 : Nat)) "source pin release left live handles or charges"
    let report := Json.mkObj [("sourceHeadsUnchanged",toJson true),("sameSourceIdentitiesAndOrder",toJson true),
      ("timings",toJson timings),("shortReplyRefused",toJson missing),("oversizedServerRequestRefused",toJson oversized),
      ("wrongManifestIsolated",toJson true),("perSourceReleaseAuthorityChecked",toJson true),
      ("normalPreparationSources",toJson prepared.size),("multiBatchInputs",toJson doubled.size),("serviceStatusAfterRelease",status),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
    let current ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
    check (toJson current == expected) "source pin audit changed original heads"
    IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
    IO.println (toJson timings).compress
  finally
    let _ ← Publication.Client.control "shutdown"
    pure ()
end Eggshell.Research.SourcePinBatchChecks
