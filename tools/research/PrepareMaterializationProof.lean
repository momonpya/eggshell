import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "materialization proof anchor changed"
  return source.replace before after
private def save (path : System.FilePath) (value : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path value

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "packet-materialize-core"
  let records := project / "docs/candidates/packet-materialize"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  check (!(← core.pathExists)) "preserve materialization diagnostic"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "packet-failure-core").toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate materialization contract"
  let handoff := core / "Eggshell/Handoff.lean"
  let source ← once (← IO.FS.readFile handoff) "def PreparedRendering.usingService"
    ((← IO.FS.readFile (project / "tools/research/PacketMaterialization.lean.inc")) ++ "\ndef PreparedRendering.usingService")
  save handoff (← once source
    ("    let some choice := pending.materialize? choice generic rows |\n" ++
     "      throw (IO.userError \"selected original packet does not fit its checked local budget\")")
    "    let choice ← IO.ofExcept (pending.materializeReport choice generic rows)")
  let source := (← IO.FS.readFile (root / "packet-failure-core/tools/research/PacketFailureHook.lean"))
    |>.replace "packet-failure" "packet-materialize"
  save (core / "tools/research/PacketMaterializeHook.lean") source
  IO.FS.createDirAll records
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("purpose",toJson "Classify the observed packet reconstruction failure in one pass: incompatible selected units or an actual packet-price violation. Prove the checked reporter's Option denotation equals the original for every input. No budget, ranking, selection, authority or fitting predicate is changed."),
    ("schedule",toJson "Reuse the packet-envelope DB/private history and unchanged 500000char/512000byte experimental envelope. Build proof, activate and verify warm, one new-session topic-1 hook. No other topics, model calls, limit sweeps or adoption."),
    ("adopted",toJson false)]).pretty
  let runtime := root / "packet-materialize-runtime-build"
  let helper := root / "packet-materialize-hook-candidate-build"
  IO.FS.writeFile (root / "packet-materialize-proof.guard.settings.json") (Json.mkObj [
    ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / "proof.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "LEAN_PATH=" ++ (runtime / "lib").toString ++ ":" ++ (core / ".lake/build/lib/lean").toString ++ ":" ++ toolchain ++ "/lib/lean",
      toolchain ++ "/bin/lean","-M2048","--root=" ++ project.toString,
      (project / "tools/research/PacketMaterializationAudit.lean").toString])]).pretty
  for (mode,output,parent,main) in [("runtime",runtime,root / "packet-failure-runtime-build","Main"),
      ("hooks",helper,runtime,"tools.research.PacketMaterializeHook")] do
    let settings := root / s!"packet-materialize-{mode}.settings.json"
    IO.FS.writeFile settings (Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
      ("toolchain",toJson toolchain),("objectModules",toJson (parent / "object-mapping.json").toString),
      ("baselineResponse",toJson (parent / "runtime.rsp").toString),("baselineMain",toJson (parent / "Main.o").toString),
      ("parents",toJson #[parent.toString,(root / "packet-failure-hook-candidate-build").toString]),
      ("force",toJson (#[] : Array String)),("mainModule",toJson main)]).pretty
    IO.FS.writeFile (root / s!"packet-materialize-{mode}-build.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (mode ++ "-build.guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]).pretty
  for (label,args) in [("describe",#["describe","candidate"]),("activate",#["activate","candidate"]),
      ("topic-1",#["run","candidate","0","1"])] do
    IO.FS.writeFile (root / s!"packet-materialize-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),
      ("command",toJson (#[helper.toString ++ "/StudyMain"] ++ args))]).pretty
