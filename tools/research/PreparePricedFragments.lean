import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "priced fragment anchor changed"
  return source.replace before after
private def save (path : System.FilePath) (value : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path value

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "priced-fragments-core"
  let records := project / "docs/candidates/priced-fragments"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  check (!(← core.pathExists)) "preserve priced fragment candidate"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "fragment-identity-core").toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate priced fragment candidate"
  let handoff := core / "Eggshell/Handoff.lean"
  let anchor := "/-- Existing fragments stay intact. Only original prepared ranges absent\n" ++
    "from them are added; a different chunk layout cannot prevent enrichment.\n" ++
    "Overlapping bytes and source envelopes must agree before any addition. -/\n" ++
    "def checkedContextExtension (prior offered : ContextDelivery)"
  let mut source := ← once (← IO.FS.readFile handoff) anchor
    ((← IO.FS.readFile (project / "tools/research/PricedFragmentAtoms.lean.inc")) ++
      "\n" ++ anchor)
  source ← once source
    "    let checked ← checkedContextExtension left right\n    pure {prior with context := some checked.val,keys := checked.val.keys,text := checked.val.render}"
    "    let checked ← checkedPricedContextAssembly left right\n    pure {prior with context := some checked.val,keys := checked.val.keys,text := checked.val.render}"
  check ((source.splitOn "Nat × Option (Nat × String × Bool)").length == 5) "unexpected price cache declarations"
  source := source.replace "Nat × Option (Nat × String × Bool)" "Nat × Option RenderFragmentKey × String"
  check ((source.splitOn "some (fragment.first,fragment.original,fragment.decoded)").length == 4) "unexpected fragment price producers"
  source := source.replace "some (fragment.first,fragment.original,fragment.decoded)" "some (fragment.renderKey context.compactCaptions)"
  check ((source.splitOn "let key := (unit.family,fragment)\n").length == 4) "unexpected price cache keys"
  source := source.replace "let key := (unit.family,fragment)\n" "let key := (unit.family,fragment,text)\n"
  save handoff source
  save (core / "tools/research/PricedFragmentAudit.lean") (← IO.FS.readFile (project / "tools/research/PricedFragmentAudit.lean"))
  let hookText := (← IO.FS.readFile (root / "fragment-identity-core/tools/research/FragmentIdentityHook.lean"))
    |>.replace "fragment-identity" "priced-fragments"
  let hookText ← once hookText "import tools.research.FragmentSourceIdentityAudit\n"
    "import tools.research.FragmentSourceIdentityAudit\nimport tools.research.PricedFragmentAudit\n"
  let hookText ← once hookText "    FragmentSourceIdentityAudit.run\n"
    "    FragmentSourceIdentityAudit.run\n    PricedFragmentAudit.run\n"
  save (core / "tools/research/PricedFragmentsHook.lean") hookText
  IO.FS.createDirAll records
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("purpose",toJson "Fix the observed price/materialization contract, not a relevance coefficient. A source record and its priced presentation have different keys. All rendering fields including JSON path and caption mode determine price; selected pieces stay whole and can only be exactly deduplicated after pricing. No post-price interval slicing/new captions."),
    ("schedule",toJson "Same protected R40 source/private history and the already-fixed 500000char/512000byte experimental envelope. Proof/fixtures before sealing, activate/warm, new-session topics1,2,3 in order. Stop at missing frozen eligible evidence or >=30s. No gold rules, limit sweeps, answering models or adoption."),
    ("adopted",toJson false)]).pretty
  let runtime := root / "priced-fragments-runtime-build"
  let helper := root / "priced-fragments-hook-candidate-build"
  for (mode,output,parent,main) in [("runtime",runtime,root / "fragment-identity-runtime-build","Main"),
      ("hooks",helper,runtime,"tools.research.PricedFragmentsHook")] do
    let settings := root / s!"priced-fragments-{mode}.settings.json"
    IO.FS.writeFile settings (Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
      ("toolchain",toJson toolchain),("objectModules",toJson (parent / "object-mapping.json").toString),
      ("baselineResponse",toJson (parent / "runtime.rsp").toString),("baselineMain",toJson (parent / "Main.o").toString),
      ("parents",toJson #[parent.toString,(root / "fragment-identity-hook-candidate-build").toString]),
      ("force",toJson (#[] : Array String)),("mainModule",toJson main)]).pretty
    IO.FS.writeFile (root / s!"priced-fragments-{mode}-build.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (mode ++ "-build.guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]).pretty
  for (label,args) in [("describe",#["describe","candidate"]),("activate",#["activate","candidate"])] ++
      [1,2,3].map (fun topic => (s!"topic-{topic}",#["run","candidate","0",toString topic])) do
    IO.FS.writeFile (root / s!"priced-fragments-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),
      ("command",toJson (#[helper.toString ++ "/StudyMain"] ++ args))]).pretty
