import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "packet failure diagnostic anchor changed"
  return source.replace before after
private def save (path : System.FilePath) (value : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path value

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "packet-failure-core"
  let records := project / "docs/candidates/packet-failure"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  check (!(← core.pathExists)) "preserve prior failure diagnostic"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "packet-envelope-core").toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate packet failure diagnostic"
  let handoff := core / "Eggshell/Handoff.lean"
  save handoff (← once (← IO.FS.readFile handoff)
    "      catch _ =>\n        Receipt.observe source.receipt \"prepared-selection-failure\" (toJson true)\n        return some pendingSearch"
    ("      catch error =>\n" ++
     "        let details ← if (← IO.getEnv \"EGGSHELL_TRACE_SERVICE_PROFILE\") == some \"1\" then\n" ++
     "          pure (Json.mkObj [(\"message\",toJson (error.toString.take 512).copy)])\n" ++
     "          else pure (toJson true)\n" ++
     "        Receipt.observe source.receipt \"prepared-selection-failure\" details\n        return some pendingSearch"))
  let mut source := (← IO.FS.readFile (root / "packet-envelope-core/tools/research/PacketEnvelopeHook.lean"))
    |>.replace "packet-envelope" "packet-failure"
  source ← once source "shared-snapshot/packet-failure-trial" "shared-snapshot/packet-envelope-trial"
  source ← once source ("          check (response.elapsedMs < 30000 && (audit.getObjValD \"availableDelivery\").getObjValD \"targetMet\" == toJson true)\n" ++
    "            \"prespecified envelope diagnostic gate failed; preserve this actual result and stop\"")
    "          check (response.elapsedMs < 30000) \"failure diagnostic exceeded the real hook deadline\""
  save (core / "tools/research/PacketFailureHook.lean") source
  IO.FS.createDirAll records
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("purpose",toJson "Explain the already observed prepared-selection-failure. The budget experiment is terminal and failed 0/3. This diagnostic preserves that result, changes only explicitly enabled error reporting and does not adjust budget, ranking or selection."),
    ("parentRuntimeSha256",toJson "ea4f588eca1257ce99779e2a950e37cc8c9ec2774ed82b5d6493d6e1ffe4b770"),
    ("schedule",toJson "Reuse the sole isolated packet-envelope DB/private history, activate the instrumented runtime and verify warm, then one topic-1 new-session actual hook. Do not run topics2/3 or answering models. Exception detail is bounded to 512 chars and remains boolean when the explicit profiling flag is absent."),
    ("limits",toJson "Hook30s, native frame8MiB, stream16MiB, RSSstop3.5GiB, free-space floor2GiB unchanged."),
    ("adopted",toJson false)]).pretty
  let runtime := root / "packet-failure-runtime-build"
  let helper := root / "packet-failure-hook-candidate-build"
  for (mode,output,parent,main) in [("runtime",runtime,root / "packet-envelope-runtime-build","Main"),
      ("hooks",helper,runtime,"tools.research.PacketFailureHook")] do
    let settings := root / s!"packet-failure-{mode}.settings.json"
    IO.FS.writeFile settings (Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
      ("toolchain",toJson toolchain),("objectModules",toJson (parent / "object-mapping.json").toString),
      ("baselineResponse",toJson (parent / "runtime.rsp").toString),("baselineMain",toJson (parent / "Main.o").toString),
      ("parents",toJson #[parent.toString,(root / "packet-envelope-hook-candidate-build").toString]),
      ("force",toJson (#[] : Array String)),("mainModule",toJson main)]).pretty
    IO.FS.writeFile (root / s!"packet-failure-{mode}-build.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (mode ++ "-build.guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]).pretty
  for (label,args) in [("describe",#["describe","candidate"]),("activate",#["activate","candidate"]),
      ("topic-1",#["run","candidate","0","1"])] do
    IO.FS.writeFile (root / s!"packet-failure-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),
      ("command",toJson (#[helper.toString ++ "/StudyMain"] ++ args))]).pretty
