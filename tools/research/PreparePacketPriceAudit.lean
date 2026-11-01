import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "packet price diagnostic anchor changed"
  return source.replace before after
private def save (path : System.FilePath) (value : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path value

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "packet-price-audit-core"
  let records := project / "docs/candidates/packet-price-audit"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  check (!(← core.pathExists)) "preserve price audit candidate"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "priced-fragments-core").toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate price audit"
  let handoff := core / "Eggshell/Handoff.lean"
  let source ← once (← IO.FS.readFile handoff) "def PreparedRendering.usingService"
    ((← IO.FS.readFile (project / "tools/research/PacketPriceAccounting.lean.inc")) ++ "\ndef PreparedRendering.usingService")
  let source ← once source "    let choice ← IO.ofExcept (pending.materializeReport choice generic rows)"
    ("    let materialized ← (← IO.mkRef (pending.materializeReport choice generic rows)).get\n" ++
     "    if (← IO.getEnv \"EGGSHELL_TRACE_SERVICE_PROFILE\") == some \"1\" && materialized.toOption.isNone then\n" ++
     "      Publication.Stream.profile \"packet-price-audit\" [(\"accounting\",pending.priceAccounting query choice generic rows)]\n" ++
     "    let choice ← IO.ofExcept materialized")
  save handoff source
  let hookText := (← IO.FS.readFile (core / "tools/research/PricedFragmentsHook.lean"))
    |>.replace "priced-fragments" "packet-price-audit"
  let hookText ← once hookText "\"render-automatic-profile\"]"
    "\"render-automatic-profile\",\"packet-price-audit\"]"
  let hookText ← once hookText
    "          check (response.elapsedMs < 30000 && (audit.getObjValD \"availableDelivery\").getObjValD \"targetMet\" == toJson true)"
    "          check (response.elapsedMs < 30000)"
  save (core / "tools/research/PacketPriceAuditHook.lean") hookText
  IO.FS.createDirAll records
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("purpose",toJson "Account for the failed fixed-envelope packet: owner presentation charges versus exact rendered owner pieces, and fixed outer-frame quotation versus actual outer frame. Trace-only after rejection; no fitting, ranking, budget or original-data change."),
    ("schedule",toJson "Same protected R40, MiniLM and fixed 500000char/512000byte envelope. One new-session topic-1 diagnostic only. No models, other topics, envelope adjustment or adoption."),
    ("adopted",toJson false)]).pretty
  let runtime := root / "packet-price-audit-runtime-build"
  let helper := root / "packet-price-audit-hook-candidate-build"
  for (mode,output,parent,main) in [("runtime",runtime,root / "priced-fragments-runtime-build","Main"),
      ("hooks",helper,runtime,"tools.research.PacketPriceAuditHook")] do
    let settings := root / s!"packet-price-audit-{mode}.settings.json"
    IO.FS.writeFile settings (Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
      ("toolchain",toJson toolchain),("objectModules",toJson (parent / "object-mapping.json").toString),
      ("baselineResponse",toJson (parent / "runtime.rsp").toString),("baselineMain",toJson (parent / "Main.o").toString),
      ("parents",toJson #[parent.toString,(root / "priced-fragments-hook-candidate-build").toString]),
      ("force",toJson (#[] : Array String)),("mainModule",toJson main)]).pretty
    IO.FS.writeFile (root / s!"packet-price-audit-{mode}-build.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (mode ++ "-build.guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]).pretty
  IO.FS.writeFile (root / "packet-price-audit-kernel.guard.settings.json") (Json.mkObj [
    ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / "kernel.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "LEAN_PATH=" ++ (root / "priced-fragments-runtime-build/lib").toString ++ ":" ++
      (core / ".lake/build/lib/lean").toString ++ ":" ++ toolchain ++ "/lib/lean",
      toolchain ++ "/bin/lean","-M3072","--root=" ++ core.toString,handoff.toString])]).pretty
  for (label,args) in [("describe",#["describe","candidate"]),("activate",#["activate","candidate"]),
      ("topic-1",#["run","candidate","0","1"])] do
    IO.FS.writeFile (root / s!"packet-price-audit-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),
      ("command",toJson (#[helper.toString ++ "/StudyMain"] ++ args))]).pretty
