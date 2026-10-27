import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def replaceOne (text before after : String) : IO String := do
  unless (text.splitOn before).length == 2 do throw (IO.userError "rollback pattern is not unique")
  return text.replace before after

def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let backup := root / "discarded-source-rpc"
  unless !(← backup.pathExists) do throw (IO.userError "preserve the prepared removal record")
  let files := #["SynapticQuery","SynapticRoutingStore","CanonicalSourcePrepared","PublicationClient",
    "PublicationService","SynapseRecommend","SynapticTransport","SynapseTransport"]
  let hashes ← IO.Process.output {
    cmd := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/assessed-controller"
    args := #["artifacts"] ++ files.map (fun name => (root / "checkout/Eggshell" / (name ++ ".lean")).toString)}
  unless hashes.exitCode == 0 do throw (IO.userError hashes.stderr)
  IO.FS.createDirAll backup
  IO.FS.writeFile (backup / "before-digests.json") hashes.stdout
  for name in files do
    IO.FS.writeBinFile (backup / (name ++ ".lean")) (← IO.FS.readBinFile (root / "checkout/Eggshell" / (name ++ ".lean")))
  for name in ["PublicationClient","PublicationService","CanonicalSourcePrepared"] do
    let saved := project / "docs/candidates/shared-original-structure/final/contracts" / ("Eggshell." ++ name ++ ".source")
    let source ← IO.ofExcept (Json.parse (← IO.FS.readFile saved) >>= fromJson? (α := Array Json))
    let some first := source[0]? | throw (IO.userError "saved source stamp is empty")
    IO.FS.writeFile (root / "checkout/Eggshell" / (name ++ ".lean")) (← IO.ofExcept first.getStr?)
  let recommend := root / "checkout/Eggshell/SynapseRecommend.lean"
  let text ← IO.FS.readFile recommend
  let text ← replaceOne text "readDeadline (allowUsage := true)" "readDeadline"
  let text ← replaceOne text
    "    let opened ← readablePrepared? fun storage => Index.open? source storage .shared\n    let shared ← match canonical.bind (·.access.index),opened with\n      | some basis,some reader => pure (some (← SharedQuery.atHead source reader basis))\n      | _,_ => pure opened\n    return {\n      source := source,shared\n"
    "    return {\n      source := source,shared := ← readablePrepared? fun storage => Index.open? source storage .shared\n"
  IO.FS.writeFile recommend text
  IO.println "Captured the rejected source RPC and restored its three unchanged base modules and local reader preparation"
