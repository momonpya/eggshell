import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def write (path : System.FilePath) (text : String) : IO Unit := do
  IO.FS.createDirAll path.parent.get!
  if ← path.pathExists then
    unless (← IO.FS.readFile path) == text do throw (IO.userError s!"keep earlier evidence: {path}")
  else IO.FS.writeFile path text

private def copyIf (source target : System.FilePath) : IO Unit := do
  if ← source.pathExists then write target (← IO.FS.readFile source)

private def compact (records : System.FilePath) : IO Unit := do
  let guards := records / "guards"
  if ← guards.pathExists then
    let mut entries := #[]
    for entry in ← guards.readDir do
      entries := entries.push (entry.fileName,← read entry.path)
    let value := toJson (entries.qsort fun a b => a.1 < b.1)
    write (records / "guards.json") value.pretty
    unless (← read (records / "guards.json")) == value do throw (IO.userError "guard ledger did not round-trip")
    IO.FS.removeDirAll guards
  for run in ["native-captured","native-generation","native-literal-usage","native-owned-readers","native-dependency-closed"] do
    let directory := records / run
    if !(← directory.pathExists) then continue
    let mut commands := #[]
    let mut retired := #[]
    for entry in ← directory.readDir do
      if !(← entry.path.isDir) then continue
      if !(← (entry.path / "record.json").pathExists) then continue
      let mut files := []
      for name in ["stdin","stdout","stderr"] do
        if ← (entry.path / name).pathExists then
          files := files ++ [(name,toJson (← IO.FS.readFile (entry.path / name)))]
      commands := commands.push (entry.fileName,Json.mkObj ([("timing",← read (entry.path / "record.json"))] ++ files))
      retired := retired.push entry.path
    if commands.isEmpty then continue
    let value := toJson (commands.qsort fun a b => a.1 < b.1)
    write (directory / "hooks.json") value.pretty
    unless (← read (directory / "hooks.json")) == value do throw (IO.userError "literal hook records did not round-trip")
    for path in retired do IO.FS.removeDirAll path

private partial def sources (root : System.FilePath) : IO (Array System.FilePath) := do
  let mut result := #[]
  for entry in ← root.readDir do
    if [".lake",".git"].contains entry.fileName then continue
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then result := result ++ (← sources entry.path)
    else if entry.fileName.endsWith ".lean" then
      unless metadata.type == .file do throw (IO.userError "candidate source still aliases its parent")
      result := result.push entry.path
  return result

/-- Collect code and bounded text evidence, never DBs, cache payloads, service
capabilities, account configuration or an answering-model invocation. -/
def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "captured-correspondence-20261026"
  let parent := base / "shared-bundle-projection-20261026/checkout"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/captured-correspondence"
  let records := output / "records"
  if args == ["compact"] then compact records; return
  unless args.isEmpty do throw (IO.userError "CollectCapturedCorrespondence [compact]")
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  let mut patch := ""
  let mut changed := #[]
  let checkout := root / "checkout"
  for file in (← sources checkout).qsort (fun a b => a.toString < b.toString) do
    let relative := (file.toString.drop (checkout.toString.length+1)).toString
    let previous := parent / relative
    let actual ← IO.FS.readFile file
    let unchanged ← if ← previous.pathExists then pure ((← IO.FS.readFile previous) == actual) else pure false
    if unchanged then continue
    let stem := (relative.dropEnd 5).toString.replace "/" "_"
    let object := root / "product-build" / (stem ++ ".o")
    let stamp ← read (root / "product-build" / (stem ++ ".source"))
    let parts ← IO.ofExcept stamp.getArr?
    unless (parts[0]?.bind (fun value => value.getStr?.toOption)) == some actual &&
        (response.splitOn ((toJson object.toString).compress)).length == 2 &&
        (← (root / "product-build" / (stem ++ ".dependencies")).pathExists) do
      throw (IO.userError s!"candidate object is not bound to its source: {relative}")
    let included ← IO.ofExcept (parts[1]!.getArr?)
    for item in included do
      let (name,bytes) ← IO.ofExcept (fromJson? (α := String × String) item)
      unless (← IO.FS.readFile (file.parent.get! / name)) == bytes do
        throw (IO.userError s!"included bytes differ from compiled object: {relative}")
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ relative,
      "-L","b/" ++ relative,(if ← previous.pathExists then previous.toString else "/dev/null"),file.toString]}
    unless diff.exitCode == 1 do throw (IO.userError s!"cannot collect candidate diff: {relative}")
    patch := patch ++ diff.stdout
    changed := changed.push relative
  write (output / "core.patch") patch
  write (records / "link-boundary.json") (Json.mkObj [("files",toJson changed),
    ("sourceStampExact",toJson true),("includeBytesExact",toJson true),
    ("selectedObjectsExact",toJson true),("dependencyClosuresPresent",toJson true)]).pretty
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let guard ← read entry.path
    unless (guard.getObjValAs? String "state").toOption == some "finished" &&
        (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError s!"capture trial is still active: {entry.fileName}")
    copyIf entry.path (records / "guards" / entry.fileName)
  for name in ["materialized-sources.json","checks-retirement.json"] do
    copyIf (root / name) (records / name)
  for name in ["Eggshell_ContractAudit-lean.stdout","tests_FullSearchOracle-lean.stdout",
      "tools_research_CapturedCorrespondenceContract-lean.stdout","build.json"] do
    copyIf (root / "contract-build" / name) (records / "contracts" / name)
  copyIf (root / "product-build/build.json") (records / "product-build.json")
  for run in ["capture-native","final-capture","presentation-capture","capture-dependency-closed",
      "atomic-source","atomic-affected","atomic-owner-delta","atomic-dependency-closed","build-resume"] do
    copyIf (root / run / "results.json") (records / run / "results.json")
  let mut nativeTrials := #[]
  for run in ["native-captured","native-generation","native-literal-usage","native-owned-readers","native-dependency-closed"] do
    let fixture := root / run / "native"
    for name in ["result.json","recovery.json","recall-required-before-delivery.json","recall-audit.json",
        "recall-body.txt","shutdown.json","publisher-shutdown.json","recall-shutdown.json","recall-publisher-shutdown.json"] do
      copyIf (fixture / name) (records / run / name)
    if !(← fixture.pathExists) then continue
    for entry in ← fixture.readDir do
      if !(← entry.path.isDir) || !(← (entry.path / "record.json").pathExists) then continue
      for name in ["record.json","stdin","stdout","stderr"] do
        copyIf (entry.path / name) (records / run / entry.fileName / name)
    let data := fixture / "recall-data/receipts"
    if ← data.pathExists then
      for entry in ← data.readDir do
        for name in ["delivery-domain.json","canonical-source-reuse.json","canonical-source-failure.json",
            "selection-plan.json","search-discovery.json","search-focus.json"] do
          copyIf (entry.path / name) (records / run / "receipts" / entry.fileName / name)
    if ← (fixture / "recall-hook/record.json").pathExists then
      nativeTrials := nativeTrials.push (Json.mkObj [("run",toJson run),
        ("timing",← read (fixture / "recall-hook/record.json")),
        ("requiredDelivery",(← read (fixture / "recall-audit.json")).getObjValD "requiredDelivery")])
  write (records / "actual-trials.json") (toJson nativeTrials).pretty
  let artifact ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString]}
  unless artifact.exitCode == 0 do throw (IO.userError artifact.stderr)
  write (records / "runtime.json") artifact.stdout
  write (records / "collection.json") (Json.mkObj [("changedFiles",toJson changed.size),
    ("answeringModelCalls",toJson (0 : Nat)),("answeringStages",toJson (0 : Nat)),
    ("llvmFrozenItemsRemeasured",toJson false),("productionAdoption",toJson false),
    ("archivesCreated",toJson false)]).pretty
  compact records
  IO.println s!"Collected {changed.size} isolated product source changes"
