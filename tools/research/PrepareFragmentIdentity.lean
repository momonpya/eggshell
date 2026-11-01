import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "source identity anchor changed"
  return source.replace before after
private def save (path : System.FilePath) (value : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path value

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "fragment-identity-core"
  let records := project / "docs/candidates/fragment-identity"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  check (!(← core.pathExists)) "preserve source identity candidate"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "packet-materialize-core").toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate source identity candidate"
  let handoff := core / "Eggshell/Handoff.lean"
  save handoff (← once (← IO.FS.readFile handoff)
    "  first < last → next.decoded = prior.decoded ∧\n"
    "  first < last →\n")
  save (core / "tools/research/FragmentSourceIdentityAudit.lean")
    (← IO.FS.readFile (project / "tools/research/FragmentSourceIdentityAudit.lean"))
  let source := (← IO.FS.readFile (root / "packet-materialize-core/tools/research/PacketMaterializeHook.lean"))
    |>.replace "packet-materialize" "fragment-identity"
  let source ← once source "import tools.research.FrozenCanonicalBasis\n"
    "import tools.research.FrozenCanonicalBasis\nimport tools.research.FragmentSourceIdentityAudit\n"
  let source ← once source "    CheckedOriginalFixtures.verify\n"
    "    FragmentSourceIdentityAudit.run\n    CheckedOriginalFixtures.verify\n"
  let source ← once source "          check (response.elapsedMs < 30000) \"failure diagnostic exceeded the real hook deadline\""
    ("          check (response.elapsedMs < 30000 && (audit.getObjValD \"availableDelivery\").getObjValD \"targetMet\" == toJson true)\n" ++
     "            \"source identity candidate failed its declared delivery/deadline gate\"")
  save (core / "tools/research/FragmentIdentityHook.lean") source
  IO.FS.createDirAll records
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("purpose",toJson "A display-decoding preference is not original-source identity. Remove only decoded equality from overlapping raw fragment agreement; retain envelope identity and exact overlapping original characters. Preserve old accepted raw agreements, reject conflicting originals, and test mixed representations/Unicode/partial overlap before actual hooks."),
    ("treatment",toJson "The same prior 500000char/512000byte isolated envelope, same candidates, scores, selector, graph, authority and raw bytes. The reference materialization reporter remains equivalent to its Option boundary. This is a source-compatibility correction, not another relevance weight."),
    ("schedule",toJson "Reuse the packet-envelope R40 DB/private history. Native proof/fixtures before sealing; activate and verify warm. Actual new-session topics1,2,3 in order, one each. Stop at any missing frozen eligible item, incomplete hook or >=30s; no model calls, new seed or adoption in this diagnostic."),
    ("adopted",toJson false)]).pretty
  let runtime := root / "fragment-identity-runtime-build"
  let helper := root / "fragment-identity-hook-candidate-build"
  for (mode,output,parent,main) in [("runtime",runtime,root / "packet-materialize-runtime-build","Main"),
      ("hooks",helper,runtime,"tools.research.FragmentIdentityHook")] do
    let settings := root / s!"fragment-identity-{mode}.settings.json"
    IO.FS.writeFile settings (Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
      ("toolchain",toJson toolchain),("objectModules",toJson (parent / "object-mapping.json").toString),
      ("baselineResponse",toJson (parent / "runtime.rsp").toString),("baselineMain",toJson (parent / "Main.o").toString),
      ("parents",toJson #[parent.toString,(root / "packet-materialize-hook-candidate-build").toString]),
      ("force",toJson (#[] : Array String)),("mainModule",toJson main)]).pretty
    IO.FS.writeFile (root / s!"fragment-identity-{mode}-build.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (mode ++ "-build.guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]).pretty
  for (label,args) in [("describe",#["describe","candidate"]),("activate",#["activate","candidate"])] ++
      [1,2,3].map (fun topic => (s!"topic-{topic}",#["run","candidate","0",toString topic])) do
    IO.FS.writeFile (root / s!"fragment-identity-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),
      ("command",toJson (#[helper.toString ++ "/StudyMain"] ++ args))]).pretty
