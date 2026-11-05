import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin Eggshell.Persistence.Store
namespace Eggshell.Research.FocusDirectoryChecks

#print axioms FocusDocument.windows_exact
#print axioms FocusDocument.cache_exact
#print axioms FocusDocument.window_original

run_meta do
  let environment ← getEnv
  let some actual := (environment.find? ``federatedDiscovery).bind (·.value?) |
    throwError "Missing actual federated discovery"
  for required in #[``FocusDocument.request,``FocusDocument.work,``FocusDocument.window] do
    unless actual.getUsedConstants.contains required do
      throwError "Actual discovery bypasses the retained source directory: {required}"
  unless !actual.getUsedConstants.contains ``SourceDelta.documents do
    throwError "Actual discovery still rediscovers source directories"
  let some repair := (environment.find? ``FocusDocument.window).bind (·.value?) |
    throwError "Missing original window repair"
  unless repair.getUsedConstants.contains ``readSearchWindow &&
      !repair.getUsedConstants.contains ``SourceDelta.documents do
    throwError "Repair does not retain the original bounded/checksummed read"

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool :=
  try let _ ← action; pure false catch _ => pure true

def run (root : System.FilePath) : IO Unit := do
  let project ← ProjectStore.openProject root
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let sources := view.sources
  let readers ← NodeReaders.new sources
  let mut documents := 0
  let mut windows := 0
  let mut negatives := 0
  for source in List.finRange sources.size do
    let snapshot := sources[source]
    for original in ← searchDocuments snapshot do
      let row : FocusDocument sources := ⟨source,original,9000000+documents,8000000+documents⟩
      check (row.request.owner == row.owner && row.request.work == row.family &&
        row.request.windows == original.windows) "query names changed original window positions"
      let old ← SourceDelta.documents snapshot [original.owner]
      let some old := old.head? | throw (IO.userError "old directory oracle omitted an original")
      check (old.owner == original.owner && old.work == original.work && old.windows == original.windows)
        "retained directory differs from independent source reload"
      let header ← locateOutcome snapshot original.owner
      let expectedWork ← (readers.at source).read header.header.work
      let some expectedText := Matcher.atomText? expectedWork | throw (IO.userError "fixture Work not textual")
      check ((← row.work readers) == expectedText) "retained Work differs from original header lookup"
      for index in ([0,original.windows.length/2,original.windows.length-1].eraseDups) do
        check ((← row.window index) == (← readSearchWindow snapshot old index))
          "retained window bytes differ from original reloaded directory"
        windows := windows+1
      if documents < 16 then
        check (← rejected (row.window original.windows.length)) "missing window was accepted"
        let bad := {row with original := {original with windows := "invalid"::original.windows.drop 1}}
        check (← rejected (bad.window 0)) "changed window digest was accepted"
        let wrong := {row with original := {original with work := original.owner}}
        check (← rejected (wrong.window 0)) "foreign Work was accepted"
        negatives := negatives+3
      documents := documents+1
  for source in List.finRange sources.size do
    check ((← DB.PageMap.pin sources[source].directory).head == sources[source].head) "comparison changed an original"
  IO.println (Json.mkObj [("allPassed",toJson true),("sources",toJson sources.size),
    ("documents",toJson documents),("windowByteComparisons",toJson windows),
    ("invalidRequestsRejected",toJson negatives),("originalHeadsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.FocusDirectoryChecks
