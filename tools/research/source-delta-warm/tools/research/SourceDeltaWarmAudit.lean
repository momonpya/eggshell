import Eggshell.Warm

open Lean Eggshell Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def signature (rows : List Warm.Window) : List String :=
  (rows.map fun row => (toJson (row.document.owner,row.index,row.key,row.start)).compress).mergeSort (· ≤ ·)

def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "SourceDeltaWarmAudit SOURCE NEW-OUTPUT")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "preserve previous source-delta audit"
  FileSystem.privateDirectory output
  let source ← DB.PageMap.pin (.mk database)
  let original := source.head
  let mut current := source.head
  let mut basis := source.head
  let mut found := false
  for _ in [:min 64 source.head.revision] do
    let publication ← readPublication {source with head := current} current.revision
    let changed ← SourceDelta.documents source publication.change.added
    if !changed.isEmpty then
      basis := publication.parent
      found := true
      break
    current := publication.parent
  check found "no bounded real publication with live added owners"
  let some history ← DB.PageMap.HistoryReader.make? source basis |
    throw (IO.userError "real source history not retained")
  let command := [(← IO.appPath).withFileName "eggshell" |>.toString,"search-provider"]
  let target : Plugin.IndexTarget := {
    owner := DB.Sidecar.Owner.ofSnapshot source
    command := command
    storage := .user }
  let settings ← Warm.options source command .user
  let (baseDiscovery,baseFocus) ← Warm.planWindows history.snapshot false
  let validatedBase ← SearchProvider.prepareMatrix settings ((baseDiscovery++baseFocus).map (·.key))
  check (validatedBase.produced == 0) "prepared superset does not cover the historical source"
  Warm.mark target history.snapshot
  let started ← IO.monoMsNow
  let (fullDiscovery,fullFocus) ← Warm.planWindows source false
  let fullPlanMs := (← IO.monoMsNow)-started
  source.cache.set {}
  source.reads.set 0
  source.readBytes.set 0
  let started ← IO.monoMsNow
  let selected ← Warm.plan source target false false
  let deltaPlanMs := (← IO.monoMsNow)-started
  let deltaPageReads ← source.reads.get
  let deltaReadBytes ← source.readBytes.get
  check (selected.scope == "publication-delta" && selected.owners > 0) "real history selected full planning"
  let owners := hashDistinct (selected.windows.1.map (·.document.owner))
  check (signature selected.windows.1 == signature (fullDiscovery.filter (fun row => owners.contains row.document.owner)) &&
    signature selected.windows.2 == signature (fullFocus.filter (fun row => owners.contains row.document.owner)))
    "real delta windows differ from full planning for the changed owners"
  let inspected ← Warm.inspectWindows source settings selected.windows.1 selected.windows.2
  check (inspected.needed.isEmpty) "real selected inputs are not already prepared"
  let projected ← SearchProvider.prepareMatrix settings ((selected.windows.1++selected.windows.2).map (·.key))
  check (projected.produced == 0 && projected.requested == inspected.coverage.windows &&
    projected.requested < (hashDistinct ((fullDiscovery++fullFocus).map (·.key))).length)
    "numerical preparation still received the entire real corpus"
  Warm.mark target source
  let started ← IO.monoMsNow
  let repeated ← Warm.plan source target false false
  let repeatedMs := (← IO.monoMsNow)-started
  check (repeated.windows.1.isEmpty && repeated.windows.2.isEmpty &&
    (← DB.PageMap.pin source.directory).head == original) "unchanged planning read windows or changed source"
  let report := Json.mkObj [
    ("source",toJson source.head),("basis",toJson basis),
    ("validatedPreparedBase",toJson validatedBase),
    ("fullDistinctKeys",toJson (hashDistinct ((fullDiscovery++fullFocus).map (·.key))).length),
    ("fullPlanMs",toJson fullPlanMs),("deltaPlanMs",toJson deltaPlanMs),
    ("changedOwners",toJson selected.owners),("publications",toJson selected.publications),
    ("deltaPhysicalPageReads",toJson deltaPageReads),("deltaPhysicalReadBytes",toJson deltaReadBytes),
    ("deltaInputCoverage",toJson inspected.coverage),("deltaProjections",toJson projected),
    ("unchangedPlanMs",toJson repeatedMs),("changedWindowsEqualFullPlan",toJson true),
    ("originalSourceUnchanged",toJson true),("fullWarmMeasured",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println report.compress
