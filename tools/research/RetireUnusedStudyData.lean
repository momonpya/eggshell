import Eggshell.DB.CacheReclaim
import Lean.Data.Json.FromToJson

open Lean Eggshell

private def base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
private def current := base / "study-services-20261026"

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total + (← bytes entry.path)
    return total
  return if metadata.type == .file then metadata.byteSize.toNat else 0

private partial def candidates (root : System.FilePath) : IO (Array System.FilePath) := do
  let mut result := #[]
  for entry in ← root.readDir do
    if entry.path == current || entry.fileName == "numerical-owned-20261024" then continue
    let metadata ← entry.path.symlinkMetadata
    if metadata.type != .file && metadata.type != .dir then continue
    if entry.fileName.endsWith ".egg" then
      result := result.push entry.path
    else if metadata.type == .dir then
      if #[".git","build","lib","models","runtime"].contains entry.fileName then continue
      if #["scale-data","scale-data-50000","fixture-data","cursor-fixture-data",
          "atomic-data","atomic-retention-data","mutation-retention-data","bootstrap-data"].contains entry.fileName then
        result := result.push entry.path
      else result := result ++ (← candidates entry.path)
  return result

def main (args : List String) : IO UInt32 := do
  try
    let [mode,report] := args | throw (IO.userError "RetireUnusedStudyData inspect|delete NEW-REPORT")
    unless mode == "inspect" || mode == "delete" do throw (IO.userError "explicit cleanup mode required")
    let report := System.FilePath.mk report
    unless report.isAbsolute && !(← report.pathExists) do throw (IO.userError "keep previous cleanup evidence")
    let roots := #[base,System.FilePath.mk "/Users/ovm/Code/eggshell/.private/product-hunt-demo",
      System.FilePath.mk "/Users/ovm/Code/eggshell-benchmarks/.lake"]
    let mut targets := #[]
    for root in roots do
      if ← root.pathExists then targets := targets ++ (← candidates root)
    -- Retired reranking experiments are independent of both retained MiniLM
    -- embedding installations. Neither the shared model nor its venv is removed.
    let models := System.FilePath.mk "/Users/ovm/.local/share/eggshell/minilm/models"
    for name in #["models--jinaai--jina-reranker-v1-tiny-en",
        "models--Xenova--ms-marco-MiniLM-L-6-v2","models--hotchpotch--japanese-reranker-tiny-v2"] do
      let path := models / name
      if ← path.pathExists then targets := targets.push path
    let mut rows := #[]
    let mut total := 0
    for path in targets do
      let count ← bytes path
      total := total+count
      rows := rows.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson count)])
    let readCache := System.FilePath.mk "/Users/ovm/.local/share/eggshell/plugin/read-cache"
    let before ← if ← readCache.pathExists then bytes readCache else pure 0
    IO.FS.writeFile report (Json.mkObj [("mode",toJson mode),("targets",toJson rows),
      ("logicalBytes",toJson total),("orphanCacheBytesBefore",toJson before),
      ("archives",toJson false),("currentStudyAndSharedMiniLMRetained",toJson true)]).pretty
    if mode == "delete" then
      for path in targets do
        if (← path.symlinkMetadata).type == .dir then IO.FS.removeDirAll path else IO.FS.removeFile path
      -- The installed collector proves all registered DB copies dead and fences
      -- registrations/indexers. Unknown, live or unreadable owners are retained.
      let deadline := (← IO.monoMsNow)+5000
      let mut removed := 0
      for _ in [:8] do
        if (← IO.monoMsNow) ≥ deadline then break
        removed := removed + (← DB.Sidecar.collect deadline)
      let after ← if ← readCache.pathExists then bytes readCache else pure 0
      IO.FS.writeFile (report.withExtension "result.json") (Json.mkObj [
        ("targetsRemoved",toJson targets.size),("logicalBytesRemoved",toJson total),
        ("orphanCachesRemoved",toJson removed),("orphanCacheBytesBefore",toJson before),
        ("orphanCacheBytesAfter",toJson after),("archives",toJson false)]).pretty
    IO.println (Json.mkObj [("mode",toJson mode),("targets",toJson targets.size),
      ("logicalBytes",toJson total),("report",toJson report.toString)]).compress
    return 0
  catch error => IO.eprintln error.toString; return 1
