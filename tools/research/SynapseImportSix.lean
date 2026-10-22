import Eggshell.SynapseImport

open Lean Eggshell Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def authoritative (source : DB.PageMap.Snapshot) : IO (Array DB.PageMap.Row) := do
  let some root := source.head.root | return #[]
  source.foldRange ⟨root.first, root.last ++ "\x00"⟩ (fun rows row =>
    pure (if DB.PageMap.derivedKey row.1 || row.1.startsWith "change:" then rows else rows.push row)) #[]

/-- Migrate copies only. The extractor receives the native source and one
frozen, causal seed recording. Questions, requirements and later feedback
are carried unchanged to the separate delivery auditor, never inspected here. -/
def main (args : List String) : IO Unit := do
  let [directory, specification, recording] := args |
    throw (IO.userError "SynapseImportSix NEW-ROOT FROZEN-SPEC SEED-RPC")
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute migration root required")
  let rows ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= Json.getArr?)
  check (rows.size == 6) "all six frozen stages are required"
  IO.FS.createDirAll root
  let mut migrated : Array Json := #[]
  let mut reports : Array Json := #[]
  for index in [:rows.size] do
    let row := rows[index]!
    let stage ← IO.ofExcept (row.getObjValAs? Nat "stage")
    check (stage == index+1) "migration order must start at topic 1"
    let original := System.FilePath.mk (← IO.ofExcept (row.getObjValAs? String "source"))
    let files ← IO.ofExcept (row.getObjValAs? (Array (String × String)) "files")
    for (name, expected) in files do
      check (Sha256.hex (← IO.FS.readBinFile (original / name)) == expected) "frozen source changed before migration"
    let destination := root / s!"stage{stage}.egg"
    let copied ← IO.Process.output {cmd := "/bin/cp", args := #["-cR", original.toString, destination.toString]}
    check (copied.exitCode == 0) copied.stderr
    let source ← DB.PageMap.pin destination
    let authoritativeBefore ← authoritative source
    let pageBytes ← IO.FS.readBinFile (DB.PageMap.dataPath destination source.head)
    let plan ← Import.plan source #[.mk recording]
    IO.FS.writeFile (root / s!"stage{stage}-plan.json") (toJson plan).compress
    let updated ← Provenance.publish source plan.origins
    check (updated.head.identity == source.head.identity && updated.head.authority == source.head.authority &&
      (← Index.sameSources updated source.head) && (← authoritative updated) == authoritativeBefore)
      "migration changed authoritative source rows"
    let afterBytes ← IO.FS.readBinFile (DB.PageMap.dataPath destination updated.head)
    check (afterBytes.extract 0 pageBytes.size == pageBytes) "migration rewrote an existing DB page"
    let derived ← Provenance.derive updated
    let consumed := derived.graph.snapshot.filter fun fact => match fact with | .consumed _ => true | _ => false
    let indexed ← Build.refresh updated .database
    let mut updatedFiles : Array (String × String) := #[]
    for (name, _) in files do
      updatedFiles := updatedFiles.push (name, Sha256.hex (← IO.FS.readBinFile (destination / name)))
    migrated := migrated.push (row.setObjVal! "source" (toJson destination.toString)
      |>.setObjVal! "files" (toJson updatedFiles))
    reports := reports.push (Json.mkObj [("stage", toJson stage), ("original", toJson original.toString),
      ("sourceHead", toJson source.head), ("migratedHead", toJson updated.head),
      ("matched", toJson plan.matched), ("alreadyPresent", toJson plan.alreadyPresent),
      ("outputMismatch", toJson plan.outputMismatch), ("ambiguous", toJson plan.ambiguous),
      ("consumptionFacts", toJson consumed.size), ("indexed", toJson indexed),
      ("authoritativeRowsUnchanged", toJson true), ("originalPagePrefixUnchanged", toJson true)])
    IO.FS.writeFile (root / "reports.json") (toJson reports).compress
    for (name, expected) in files do
      check (Sha256.hex (← IO.FS.readBinFile (original / name)) == expected) "migration modified a canonical source"
  IO.FS.writeFile (root / "frozen-spec.json") (toJson migrated).compress
  IO.println (toJson reports).compress
