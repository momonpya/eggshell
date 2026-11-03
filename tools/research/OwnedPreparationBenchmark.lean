import Eggshell.Warm
import Eggshell.ContractAudit

open Lean Eggshell DB Persistence.Store

namespace Eggshell.Research.OwnedPreparationBenchmark

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def outcome (i : Nat) : Value := .apply .outcome (.semantic
  (.text s!"inspect kernelsignal{i}") (.semantic
    (.text (s!"original observation kernelsignal{i} " ++ String.join (List.replicate 70 "evidence "))) .nil))

def make (root : System.FilePath) (count : Nat) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "new absolute source fixture required"
  FileSystem.privateDirectory root
  let base ← PageMap.create (root / "source.egg") "owned-ready-benchmark"
  let _ ← PageMap.withWriter base fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let added ← (List.range count |>.map outcome).mapM intern.root
    writeChange writer {added,removed := [],unionsChanged := false}
  IO.println (toJson (← PageMap.pin base.directory).head).compress

/-- The parent entry uses serial preparation; the candidate replaces only
this wrapper with Warm.prepareSourceIndexes. Product sources stay isolated. -/
def prepare (source : PageMap.Snapshot) : IO (WindowOwners.Result × RetrievalResearch.Index.Result) := do
  let windows ← WindowOwners.refresh source .user
  let lexical ← RetrievalResearch.Index.warm source .user
  return (windows,lexical)

def run (directory root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "new absolute run directory required"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString)
    "separate private DB-scoped derived root required"
  FileSystem.privateDirectory root
  let source ← PageMap.pin directory
  let started ← IO.monoMsNow
  let (windows,lexical) ← prepare source
  let elapsed := (← IO.monoMsNow)-started
  let some reader ← RetrievalResearch.Index.open? source | throw (IO.userError "lexical view absent")
  let original ← NodeReader.new source
  let documents ← searchDocuments source
  let terms ← documents.mapM fun document => do
    let value ← original.outcome (← original.locateOutcome document.owner)
    return (document.owner,RetrievalResearch.tokens (searchText value))
  for term in hashDistinct (terms.flatMap Prod.snd) ++ ["w:absent"] do
    let (observed,count) ← reader.posting term
    let expected := (terms.filter (fun row => row.2.contains term)).map Prod.fst
    check (observed.mergeSort (· ≤ ·) == expected.mergeSort (· ≤ ·) && count == expected.length)
      "lexical postings differ from independent original scan"
  let some ready ← WindowOwners.open? source .user | throw (IO.userError "window view absent")
  let mut expected := []
  for document in documents do
    let ordinal ← getNat source.get (key "member" document.owner)
    expected := expected ++ WindowOwners.entries document ordinal
  let found ← WindowOwners.lookup ready (hashDistinct (expected.map Prod.fst)) 8192
  check (found.val.partialKeys.isEmpty && found.val.occurrences.length == expected.length &&
    found.val.occurrences.all expected.contains) "window postings differ from original census"
  check ((← PageMap.pin directory).head == source.head) "preparation wrote original DB"
  let result := Json.mkObj [("source",toJson source.head),("owners",toJson documents.length),
    ("preparationMs",toJson elapsed),("windows",toJson windows),("lexical",toJson lexical),
    ("postingsMatchOriginal",toJson true),("originalUnchanged",toJson true)]
  IO.FS.writeFile (root / "result.json") (result.pretty ++ "\n")
  IO.println result.compress

end Eggshell.Research.OwnedPreparationBenchmark

def main (args : List String) : IO Unit := do
  if let ["make",root,count] := args then
    let some count := count.toNat? | throw (IO.userError "invalid owner count")
    Eggshell.Research.OwnedPreparationBenchmark.make (.mk root) count
  else if let [source,root] := args then
    Eggshell.Research.OwnedPreparationBenchmark.run (.mk source) (.mk root)
  else throw (IO.userError "OwnedPreparationBenchmark make NEW_ROOT COUNT | SOURCE NEW_RUN")
