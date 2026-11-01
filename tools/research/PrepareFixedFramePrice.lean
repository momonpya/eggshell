import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "fixed frame price anchor changed"
  return source.replace before after
private def save (path : System.FilePath) (value : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path value

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "fixed-frame-price-core"
  let records := project / "docs/candidates/fixed-frame-price"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  check (!(← core.pathExists)) "preserve fixed frame candidate"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "priced-fragments-core").toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate fixed frame candidate"
  let handoff := core / "Eggshell/Handoff.lean"
  let source ← once (← IO.FS.readFile handoff) "structure PendingRendering where"
    ((← IO.FS.readFile (project / "tools/research/FixedFramePrice.lean.inc")) ++ "\nstructure PendingRendering where")
  let source ← once source "    let packetCost := fun (fitted : List TransportSlice) =>"
    "    let exactPacketCost := fun (fitted : List TransportSlice) =>"
  let source ← once source "    let finish (selectionPlan : Option SharedRangeAdapter.RenderChoice) : Option Handoff :="
    ("    -- These graph/status bounds range over the complete admitted domain,\n" ++
     "    -- not empty templates whose future evidence keys are absent. Reserve\n" ++
     "    -- both UTF-8 dimensions, policy, guidance, locators and separators.\n" ++
     "    let frameCharge := policyPacketCost policy\n" ++
     "      (reserved + evidenceGapGuidance.length + locationText.length + 3,\n" ++
     "       reservedBytes + evidenceGapGuidance.utf8ByteSize + locationText.utf8ByteSize + 3)\n" ++
     "    let packetCost := if meaningSelected && !enforce then packetFrameCharge frameCharge else exactPacketCost\n" ++
     "    let finish (selectionPlan : Option SharedRangeAdapter.RenderChoice) : Option Handoff :=")
  save handoff source
  save (core / "tools/research/FixedFramePriceAudit.lean") (← IO.FS.readFile (project / "tools/research/FixedFramePriceAudit.lean"))
  let hookText := (← IO.FS.readFile (core / "tools/research/PricedFragmentsHook.lean"))
    |>.replace "priced-fragments" "fixed-frame-price"
  let hookText ← once hookText "import tools.research.PricedFragmentAudit\n"
    "import tools.research.PricedFragmentAudit\nimport tools.research.FixedFramePriceAudit\n"
  save (core / "tools/research/FixedFramePriceHook.lean") hookText
  IO.FS.createDirAll records
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("purpose",toJson "Fix the measured outer-frame underquote (26366 quoted versus 27614 actual), not the envelope or relevance weights. Quote the complete admitted WorkGraph and source-status domain once; owner templates cannot predict visibility after source fragments are selected. All per-owner generic quotes matched actual costs in the prior diagnostic. Keep final actual wire reconciliation."),
    ("proofScope",toJson "Kernel-check arbitrary-input frame-charge independence and additive whole-slice charges. This is not a completed proof that maximal graph rendering bounds every fitted frame; final real-packet reconciliation remains necessary."),
    ("schedule",toJson "Same R40/private history/MiniLM and fixed 500000char/512000byte envelope. Proof/native fixtures, activate/warm, new-session topics1,2,3 in order. Stop at any missing frozen eligible item or >=30s; no models, new seed, sweeps, other tuning or adoption."),
    ("adopted",toJson false)]).pretty
  let runtime := root / "fixed-frame-price-runtime-build"
  let helper := root / "fixed-frame-price-hook-candidate-build"
  for (mode,output,parent,main) in [("runtime",runtime,root / "packet-price-audit-runtime-build","Main"),
      ("hooks",helper,runtime,"tools.research.FixedFramePriceHook")] do
    let settings := root / s!"fixed-frame-price-{mode}.settings.json"
    IO.FS.writeFile settings (Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
      ("toolchain",toJson toolchain),("objectModules",toJson (parent / "object-mapping.json").toString),
      ("baselineResponse",toJson (parent / "runtime.rsp").toString),("baselineMain",toJson (parent / "Main.o").toString),
      ("parents",toJson #[parent.toString,(root / "packet-price-audit-hook-candidate-build").toString]),
      ("force",toJson (#[] : Array String)),("mainModule",toJson main)]).pretty
    IO.FS.writeFile (root / s!"fixed-frame-price-{mode}-build.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (mode ++ "-build.guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]).pretty
  IO.FS.writeFile (root / "fixed-frame-price-kernel.guard.settings.json") (Json.mkObj [
    ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / "kernel.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "LEAN_PATH=" ++ (root / "packet-price-audit-runtime-build/lib").toString ++ ":" ++
      (core / ".lake/build/lib/lean").toString ++ ":" ++ toolchain ++ "/lib/lean",
      toolchain ++ "/bin/lean","-M3072","--root=" ++ core.toString,handoff.toString])]).pretty
  for (label,args) in [("describe",#["describe","candidate"]),("activate",#["activate","candidate"])] ++
      [1,2,3].map (fun topic => (s!"topic-{topic}",#["run","candidate","0",toString topic])) do
    IO.FS.writeFile (root / s!"fixed-frame-price-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),
      ("command",toJson (#[helper.toString ++ "/StudyMain"] ++ args))]).pretty
