import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "record incidence anchor changed"
  return source.replace before after
private def region (source first last replacement : String) : IO String := do
  let pieces := source.splitOn first
  check (pieces.length == 2) "record incidence region start changed"
  let rest := pieces[1]!.splitOn last
  check (rest.length == 2) "record incidence region end changed"
  return pieces[0]! ++ replacement ++ last ++ rest[1]!

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let base := root / "query-cache-baseline-core"
  let core := root / "record-incidence-core"
  check (!(← core.pathExists)) "preserve previous record-incidence candidate"
  let mut recipe ← IO.FS.readFile (base / "Eggshell/CanonicalSourceRecipe.lean")
  recipe ← once recipe "public import Eggshell.CanonicalSourceRecords\n"
    "public import Eggshell.CanonicalSourceRecords\npublic import tools.research.RecordIncidence\n"
  recipe ← region recipe "structure Stored where" "theorem Checked.catalogue_complete"
    ("structure Layout where\n" ++
     "  entries : List Entry\n  incidence : Array (List Nat)\n  deriving BEq, ToJson, FromJson\n\n" ++
     "structure Stored where\n  rows : Array StoredRow\n  layout : Layout\n  deriving BEq, ToJson, FromJson\n\n" ++
     "def compile (parts : Array StoredRow) : Except String Stored := do\n" ++
     "  let rows ← Delivery.merge parts\n  let records := Records.prepare rows\n" ++
     "  return ⟨rows,⟨records.map Entry.ofRecord,RecordIncidence.wire (records.map (·.indices))⟩⟩\n\n" ++
     "structure Checked (rows : Array StoredRow) where\n  records : List (Records.Record rows)\n" ++
     "  catalogue : List (List (Fin rows.size))\n  exact : catalogue = Records.catalogue rows records\n" ++
     "  incidence : RecordIncidence.Index (records.map (·.indices))\n\n" ++
     "def check (rows : Array StoredRow) (layout : Layout) : Except String (Checked rows) := do\n" ++
     "  let records ← layout.entries.mapM (Entry.check? rows)\n" ++
     "  let incidence ← RecordIncidence.checkWire (records.map (·.indices)) layout.incidence\n" ++
     "  return ⟨records,Records.catalogue rows records,rfl,incidence⟩\n\n" ++
     "def Checked.close (prepared : Checked rows) (requested : List (Fin rows.size)) : Array StoredRow :=\n" ++
     "  ((prepared.incidence.close requested).map (fun index => rows[index])).toArray\n\n" ++
     "theorem Checked.close_exact (prepared : Checked rows) (requested : List (Fin rows.size)) :\n" ++
     "    prepared.close requested = Records.close rows prepared.records requested := by\n" ++
     "  simp only [Checked.close,Records.close,Records.closeIndices,RecordIncidence.close_exact]\n" ++
     "  simp [List.filter_map,List.flatMap_def,Function.comp_def]\n\n")
  recipe ← region recipe "def combine (left right merged : Array StoredRow)" "def name (owner : String)"
    ("def combine (left right merged : Array StoredRow) (a b : Layout) : Except String Layout := do\n" ++
     "  let entries := hashDistinct ((← reindex left merged a.entries) ++ (← reindex right merged b.entries))\n" ++
     "  let records ← entries.mapM (Entry.check? merged)\n" ++
     "  let layout : Layout := ⟨entries,RecordIncidence.wire (records.map (·.indices))⟩\n" ++
     "  let _ ← check merged layout\n  return layout\n\n")
  let mut prepared ← IO.FS.readFile (base / "Eggshell/CanonicalSourcePrepared.lean")
  prepared ← once prepared ".getD ⟨#[],[]⟩" ".getD ⟨#[],⟨[],#[]⟩⟩"
  prepared ← once prepared "Array (String × List Recipe.Entry)" "Array (String × Recipe.Layout)"
  let service ← once (← IO.FS.readFile (base / "Eggshell/PublicationService.lean"))
    "(owner,recipe.records)" "(owner,recipe.layout)"
  let transport ← once (← IO.FS.readFile (base / "Eggshell/SynapseTransport.lean"))
    "Std.HashMap String (List CanonicalSource.Recipe.Entry)" "Std.HashMap String CanonicalSource.Recipe.Layout"
  let mut handoff ← IO.FS.readFile (base / "Eggshell/Handoff.lean")
  handoff ← once handoff "Option (List Synapses.CanonicalSource.Recipe.Entry)" "Option Synapses.CanonicalSource.Recipe.Layout"
  handoff ← once handoff "Std.HashMap String (List Synapses.CanonicalSource.Recipe.Entry)"
    "Std.HashMap String Synapses.CanonicalSource.Recipe.Layout"
  handoff ← once handoff "Synapses.CanonicalSource.Records.close family.cached records requested"
    "prepared.close requested"
  let cache ← once (← IO.FS.readFile (base / "Eggshell/CanonicalSourceCache.lean"))
    "  (include_str \"CanonicalSourceRecipe.lean\").toUTF8,"
    "  (include_str \"../tools/research/RecordIncidence.lean\").toUTF8,\n  (include_str \"CanonicalSourceRecipe.lean\").toUTF8,"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",base.toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate record-incidence source"
  for (name,text) in [("CanonicalSourceRecipe",recipe),("CanonicalSourcePrepared",prepared),
      ("PublicationService",service),("SynapseTransport",transport),("Handoff",handoff),("CanonicalSourceCache",cache)] do
    IO.FS.writeFile (core / ("Eggshell/" ++ name ++ ".lean")) text
  let helper := "tools/research/RecordIncidence.lean"
  IO.FS.createDirAll (core / helper).parent.get!
  IO.FS.writeFile (core / helper) (← IO.FS.readFile (project / helper))
  IO.println "Stored record incidence with exact ordered closure; no relevance, costs, grouping or authority changes"
