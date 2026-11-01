import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("packet envelope anchor changed: " ++ toString (before.take 90))
  return source.replace before after
private def save (path : System.FilePath) (value : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path value

def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "runtime/hooks required")
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "packet-envelope-core"
  let runtime := root / "packet-envelope-runtime-build"
  let records := project / "docs/candidates/packet-envelope"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  IO.FS.createDirAll records
  if mode == "runtime" then
    check (!(← core.pathExists)) "preserve prior packet envelope candidate"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "transport-profile-core").toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate packet envelope candidate"
    let config := core / "Eggshell/Config.lean"
    save config (← once (← IO.FS.readFile config) "def nativeHandoffBytes : Nat := 128000"
      "def nativeHandoffBytes : Nat := 512000")
    IO.FS.writeFile (records / "plan.json") (Json.mkObj [
      ("purpose",toJson "Test whether a larger transport envelope can preserve admitted original evidence, without changing scores, graph, authority, candidates or selection algorithm."),
      ("parentRuntimeSha256",toJson "27708291ad028369de099c0faef4f1ef839841262d6bd03e789ccef1ced6a0fe"),
      ("treatment",toJson "The isolated runtime has exactly one product literal change: nativeHandoffBytes 128000 to 512000. Its isolated profile uses handoff_chars 500000 instead of 120000. This is an experimental ceiling, not a new adoption or platform requirement."),
      ("schedule",toJson "Fresh isolated source/private-history fork of the same protected R40 checkpoint; reuse immutable prepared projections, verify warm. One new-session actual hook per topic 1,2,3 in order. Stop if a hook is incomplete, exceeds 30s, changes frozen source/denominator, or misses any frozen eligible item. No limit sweep or gold-dependent runtime rules."),
      ("limits",toJson "Hook 30 seconds unchanged; native frames 8MiB and streams 16MiB unchanged. Aggregate RSS stop 3.5GiB and free-space floor 2GiB. No answering-model calls or new seed in this diagnostic."),
      ("adoption",toJson "Unadopted. Actual inclusive token reduction, maintained quality and deadline in prespecified controlled repeated initial/history comparisons across topics1,2,3 are still required. More evidence is not itself adoption."),
      ("adopted",toJson false)]).pretty
  else if mode == "hooks" then
    check (← core.pathExists) "build isolated runtime first"
    let target := core / "tools/research/PacketEnvelopeHook.lean"
    check (!(← target.pathExists)) "preserve packet envelope harness"
    let mut source := (← IO.FS.readFile (root / "transport-profile-core/tools/research/TransportProfileHook.lean"))
      |>.replace "transport-profile" "packet-envelope"
      |>.replace "selection-frames-trial" "packet-envelope-trial"
    source ← once source "handoff_chars = 120000" "handoff_chars = 500000"
    source ← once source "shared-snapshot/selection-witness-trial/candidate/work.egg/derived"
      "shared-snapshot/selection-frames-trial/candidate/work.egg/derived"
    source ← once source "          check (body == (← IO.FS.readFile (project / s!\"docs/candidates/source-plan/bodies/topic-{topic}.txt\"))) \"observer changed actual parent body\""
      "          let sameParentBody := body == (← IO.FS.readFile (project / s!\"docs/candidates/source-plan/bodies/topic-{topic}.txt\"))"
    source ← once source "            (\"adopted\",toJson false),(\"nativeDeliveryAudit\",toJson audit)]).pretty"
      ("            (\"sameParentBody\",toJson sameParentBody),(\"adopted\",toJson false),(\"nativeDeliveryAudit\",toJson audit)]).pretty\n" ++
       "          check (response.elapsedMs < 30000 && (audit.getObjValD \"availableDelivery\").getObjValD \"targetMet\" == toJson true)\n" ++
       "            \"prespecified envelope diagnostic gate failed; preserve this actual result and stop\"")
    save target source
  else throw (IO.userError "unknown packet envelope mode")
  let parent := if mode == "runtime" then root / "transport-profile-runtime-build" else runtime
  let output := if mode == "runtime" then runtime else root / "packet-envelope-hook-candidate-build"
  let settings := root / s!"packet-envelope-{mode}.settings.json"
  IO.FS.writeFile settings (Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
    ("toolchain",toJson toolchain),("objectModules",toJson (parent / "object-mapping.json").toString),
    ("baselineResponse",toJson (parent / "runtime.rsp").toString),("baselineMain",toJson (parent / "Main.o").toString),
    ("parents",toJson #[parent.toString,(root / "transport-profile-hook-candidate-build").toString]),
    ("force",toJson (#[] : Array String)),
    ("mainModule",toJson (if mode == "runtime" then "Main" else "tools.research.PacketEnvelopeHook"))]).pretty
  let mut commands := [(mode ++ "-build",#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
    (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]
  if mode == "hooks" then
    commands := commands ++ [("describe",#[(output / "StudyMain").toString,"describe","candidate"]),
      ("prepare",#[(output / "StudyMain").toString,"prepare","candidate"])]
    for topic in [1,2,3] do commands := commands ++ [(s!"topic-{topic}",#[(output / "StudyMain").toString,"run","candidate","0",toString topic])]
  for (label,command) in commands do
    IO.FS.writeFile (root / s!"packet-envelope-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),
      ("command",toJson command)]).pretty
