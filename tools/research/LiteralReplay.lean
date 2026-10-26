import tools.research.StudyCommand
import tools.research.StudyRuntime
import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def originalSupports (facts : Array Fact) : Array Support := facts.filterMap fun fact =>
  match fact with
  | .supports support => if support.source.file?.isNone then some support else none
  | _ => none

private def counts (facts : Array Fact) : Json := Json.mkObj [
  ("facts",toJson facts.size),
  ("originalSupports",toJson (originalSupports facts).size),
  ("supports",toJson (facts.filter fun fact => match fact with | .supports _ => true | _ => false).size),
  ("coquoted",toJson (facts.filter fun fact => match fact with | .coquoted .. => true | _ => false).size),
  ("consumed",toJson (facts.filter fun fact => match fact with | .consumed _ => true | _ => false).size)]

private def embedded (source : DB.PageMap.Snapshot) (facts : Array Fact) (wanted : String) : IO Nat := do
  let reader ← Persistence.Store.NodeReader.new source
  let mut count := 0
  for support in originalSupports facts do
    if support.read.quotations.contains (Quotes.digest wanted) then continue
    let some id ← Build.ownerId? source support.binding.owner | continue
    let doc ← Build.document reader id
    let raw := doc.source.getD ""
    let payload := String.ofList ((raw.toList.drop support.binding.first).take
      (support.binding.limit-support.binding.first))
    if (payload.splitOn wanted).length > 1 then count := count+1
  return count

/-- Reinspect already completed warm commands without running them again.
Finding the same symbol in a separate printf output does not establish that
the source row or remote URI containing the quote acquired support. -/
private def inspect (root : System.FilePath) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let source ← DB.PageMap.pin (root / "source.egg")
  let files ← StudyRuntime.files source.directory
  check (files == (← StudyRuntime.files (base / "record-publication-20261026/final-pair/native/work.egg")))
    "the common source is no longer the frozen parent publication"
  let mut reports := #[]
  let mut results : Array (Array Fact) := #[]
  for (label,installRoot) in [("parent",base / "record-publication-20261026/final-pair/prefix"),
      ("candidate",base / "literal-support-20261026/bounded/prefix")] do
    let arm := root / label
    let warm ← IO.ofExcept (Json.parse (← IO.FS.readFile (arm / "warm/record.json")))
    check ((warm.getObjValAs? Nat "exitCode").toOption == some 0) "completed warm failed"
    let index ← DB.PageMap.pin (arm / "data/read-cache" / source.head.identity / "synapses/recommendations")
    let some manifest ← Index.manifest? index | throw (IO.userError "missing replay manifest")
    check (manifest.source == source.head && manifest.scope == .shared) "replay used another source"
    let facts ← Index.allFacts index
    Index.checkFacts source.head.identity .shared facts
    let captured ← IO.ofExcept (Json.parse (← IO.FS.readFile (arm / "facts.json")) >>= fromJson? (α := Array Fact))
    check (facts == captured) "replay facts changed after the warm command"
    let mut evidenceCounts := #[]
    for wanted in ["NEEDED_SYMBOL","customer/logs"] do
      let count ← embedded source facts wanted
      check (if label == "parent" then count == 0 else count > 0) "embedded original quote support did not separate the products"
      evidenceCounts := evidenceCounts.push (Json.mkObj [("quote",toJson wanted),("embeddedOriginalSupports",toJson count)])
    reports := reports.push (Json.mkObj [("arm",toJson label),("counts",counts facts),
      ("embedded",toJson evidenceCounts),("manifest",toJson manifest),("warm",warm),
      ("runtimeSha256",toJson (← ArtifactHash.hex (installRoot / "libexec/eggshell")))])
    results := results.push facts
  let oldCore := results[0]!.filter fun fact => match fact with | .read _ | .consumed _ => true | _ => false
  let newCore := results[1]!.filter fun fact => match fact with | .read _ | .consumed _ => true | _ => false
  check (oldCore.size == newCore.size && oldCore.all newCore.contains) "recorded reads or consumption changed"
  let report := Json.mkObj [("commonSnapshot",toJson files),("sourceHead",toJson source.head),
    ("arms",toJson reports),("parentDefectReproduced",toJson true),("originalQuoteSupportRecovered",toJson true),
    ("readsAndConsumptionUnchanged",toJson true),("sourceUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false),
    ("requiredDelivery95Established",toJson false),("totalTokenImprovementEstablished",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress

/-- Product comparison on one identical source-only checkpoint. Both warm
commands have independent private roots and may write only derived views.
This is a model-free diagnosis, not a total-token adoption experiment. -/
def main (args : List String) : IO UInt32 := do
  try
    if let ["inspect",directory] := args then
      inspect (.mk directory)
      return 0
    let [directory] := args | throw (IO.userError "LiteralReplay UNUSED-ROOT")
    let root := System.FilePath.mk directory
    check (root.isAbsolute && !(← root.pathExists)) "unused absolute replay root required"
    IO.FS.createDir root
    let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
    let parent := base / "record-publication-20261026"
    let candidate := base / "literal-support-20261026"
    let source := root / "source.egg"
    let before ← StudyRuntime.checkpoint (parent / "final-pair/native/work.egg") source
    let pinned ← DB.PageMap.pin source
    let mut reports := #[]
    let mut results : Array (Array Fact) := #[]
    for (label,installRoot) in [("parent",parent / "final-pair/prefix"),("candidate",candidate / "bounded/prefix")] do
      let arm := root / label
      IO.FS.createDir arm
      let data := arm / "data"
      IO.FS.createDir data
      let binary := installRoot / "libexec/eggshell"
      let configuration := arm / "config.toml"
      IO.FS.writeFile configuration ("default = \"work\"\nsemantic_matcher = " ++
        (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
        (toJson source.toString).compress ++ "\n[profiles.work]\nread = [\"work\"]\nhandoff_chars = 120000\n")
      let environment := #[
        ("EGGSHELL_PREFIX",some installRoot.toString),("EGGSHELL_DATA_ROOT",some data.toString),
        ("EGGSHELL_CONFIG",some configuration.toString),("LEAN_NUM_THREADS",some "1"),
        ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
        ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
      let result ← StudyCommand.run binary.toString #["egg","warm","work"] environment root.toString ""
        (arm / "warm") 60000
      check (result.exitCode == 0) ("replay warm failed: " ++ result.stderr)
      check ((← StudyRuntime.files source) == before && (← DB.PageMap.pin source).head == pinned.head)
        "warm changed the common source checkpoint"
      let path := data / "read-cache" / pinned.head.identity / "synapses" / Index.Scope.directory .shared
      let index ← DB.PageMap.pin path
      let some manifest ← Index.manifest? index | throw (IO.userError "replay has no synaptic manifest")
      check (manifest.source == pinned.head && manifest.scope == .shared) "replay used another source snapshot"
      let facts ← Index.allFacts index
      Index.checkFacts pinned.head.identity .shared facts
      IO.FS.writeFile (arm / "facts.json") (toJson facts).compress
      results := results.push facts
      reports := reports.push (Json.mkObj [("arm",toJson label),("counts",counts facts),
        ("runtimeSha256",toJson (← ArtifactHash.hex binary)),("manifest",toJson manifest),
        ("elapsedMs",toJson result.elapsedMs),("sourceUnchanged",toJson true)])
    for wanted in ["NEEDED_SYMBOL","customer/logs"] do
      check ((← embedded pinned results[0]! wanted) == 0 && (← embedded pinned results[1]! wanted) > 0)
        "same-snapshot replay did not isolate missing embedded original quote support"
    let oldCore := results[0]!.filter fun fact => match fact with | .read _ | .consumed _ => true | _ => false
    let newCore := results[1]!.filter fun fact => match fact with | .read _ | .consumed _ => true | _ => false
    check (oldCore.size == newCore.size && oldCore.all newCore.contains) "literal matching changed recorded reads or consumption"
    let result := Json.mkObj [("commonSnapshot",toJson before),("sourceHead",toJson pinned.head),
      ("arms",toJson reports),("parentDefectReproduced",toJson true),
      ("originalQuoteSupportRecovered",toJson true),("readsAndConsumptionUnchanged",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false),
      ("requiredDelivery95Established",toJson false),("totalTokenImprovementEstablished",toJson false)]
    IO.FS.writeFile (root / "result.json") result.pretty
    IO.println result.compress
    return 0
  catch error => IO.eprintln error.toString; return 1
