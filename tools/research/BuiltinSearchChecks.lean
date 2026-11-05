import Eggshell.BuiltinSearch
open Lean Eggshell Eggshell.Plugin Eggshell.DB
namespace Eggshell.Research.BuiltinSearchChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def response (related ranked : List Nat) (evidence : List (Nat × List Nat) := []) : Json :=
  Json.mkObj [("related",toJson related),("ranked",toJson ranked),
    ("evidence",toJson (evidence.map fun (document,indices) =>
      Json.mkObj [("document",toJson document),("indices",toJson indices)]))]
def describe (result : Option (SemanticMatcher.IndexedSearch documents)) : Json :=
  match result with
  | none => Json.null
  | some result => toJson (result.related.map (fun row => (row.document.owner,row.indices)),
      result.ranking.map (fun row => (row.document.owner,row.indices)),result.order.indices)
def run (root : System.FilePath) : IO Unit := do
  check (!(← (root/"report.json").pathExists)) "preserve earlier native-provider checks"
  IO.FS.createDirAll root
  let own := (← IO.appPath).toString
  check ((← BuiltinSearch.arguments? [own,"search-provider","--mode","lexical"] "search-provider") == some ["--mode","lexical"])
    "current builtin command not recognized"
  check ((← BuiltinSearch.arguments? [own,"other"] "search-provider").isNone) "foreign command recognized"
  check ((← BuiltinSearch.arguments? ["relative-runtime","search-provider"] "search-provider").isNone)
    "relative external provider treated as builtin"
  let parent := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/prepared-reader-images-build/StudyMain"
  check ((← BuiltinSearch.arguments? [parent,"search-provider"] "search-provider").isNone)
    "different configured executable treated as builtin"
  let some command ← MiniLM.command (← Paths.installRoot) | throw (IO.userError "MiniLM command unavailable")
  let texts := #[#["The amber device reports timeout after reset.","The amber device retry limit is four."],
    #["The blue device reports success after reset.","The blue device retry limit is seven."]]
  let documents := texts.toList.zipIdx.map fun (windows,index) =>
    ({owner := index,work := index,windows := windows.toList.map Persistence.Store.windowKey} : Persistence.Store.SearchDocument)
  let reads ← IO.mkRef (0 : Nat)
  let reader : SemanticMatcher.WindowReader := fun document position => do
    reads.modify (·+1)
    let some text := (texts[document.owner]?).bind (·[position.val]?) |
      throw (IO.userError "foreign transient window")
    return text
  let external ← SemanticMatcher.nominateIndexed command "What is the amber device retry limit?" documents [] [] reader false none "focus"
  let externalReads ← reads.get
  reads.set 0
  let native ← BuiltinSearch.nominateIndexed command "What is the amber device retry limit?" documents [] [] reader false none "focus"
  check (native.isSome && describe external == describe native) "transient repair or complete focus response changed"
  check (externalReads == 4 && (← reads.get) == 4) "transient repair no longer reads the same bounded windows"
  let badOrder : SemanticMatcher.IndexedExchange := fun _ _ =>
    pure (response [] [0])
  check ((← SemanticMatcher.nominateIndexedUsing badOrder "query" documents [] [] reader).isNone)
    "incomplete rank accepted"
  let badWindow : SemanticMatcher.IndexedExchange := fun _ _ =>
    pure (response [0] [0,1] [(0,[999])])
  check ((← SemanticMatcher.nominateIndexedUsing badWindow "query" documents [] [] reader).isNone)
    "foreign evidence window accepted"
  reads.set 0
  let repeated : SemanticMatcher.IndexedExchange := fun _ repair => do
    let _ ← repair 0 [0]
    let _ ← repair 0 [0]
    return response [] [0,1]
  check ((← SemanticMatcher.nominateIndexedUsing repeated "query" documents [] [] reader).isNone && (← reads.get) == 1)
    "repeated repair escaped its original bound"
  let longDocuments := [0,1].map fun index =>
    ({owner := index,work := index,windows := (List.range 32).map (fun n => toString n)} : Persistence.Store.SearchDocument)
  let count ← IO.mkRef (0 : Nat)
  let longReader : SemanticMatcher.WindowReader := fun _ _ => do
    count.modify (·+1)
    pure "owned"
  let excessive : SemanticMatcher.IndexedExchange := fun _ repair => do
    let _ ← repair 0 (List.range 32)
    let _ ← repair 1 [0]
    return response [] [0,1]
  check ((← SemanticMatcher.nominateIndexedUsing excessive "query" longDocuments [] [] longReader).isNone && (← count.get) == 32)
    "cross-document repair exceeded thirty-two windows"
  let active ← IO.mkRef false
  let finished ← IO.mkRef false
  let slow : IO Unit := do
    active.set true
    try
      repeat
        TaskDeadline.ensureLive ((← IO.monoMsNow)+1000)
        IO.sleep 5
    finally active.set false; finished.set true
  let began ← IO.monoMsNow
  let expired ← try BuiltinSearch.bounded slow 20; pure false catch _ => pure true
  check (expired && (← finished.get) && !(← active.get) && (← IO.monoMsNow)-began < 1000)
    "deadline returned with its actual task still running"
  let lock := root/"claim.guard"
  FileSystem.immutableExistingBytes lock ByteArray.empty
  let exclusive ← FileSystem.openRead lock.toString
  let waiting ← FileSystem.openRead lock.toString
  check (← FileSystem.tryReadLock exclusive true) "could not own test claim"
  let claimed ← IO.mkRef false
  let started ← IO.monoMsNow
  let cancelled ← try
      BuiltinSearch.bounded (do
        try Numerical.claim waiting false ((← IO.monoMsNow)+10000)
        finally claimed.set true) 20
      pure false
    catch _ => pure true
  FileSystem.unlockRead exclusive
  check (cancelled && (← claimed.get) && (← IO.monoMsNow)-started < 1000)
    "numerical startup claim ignored cancellation"
  let report := Json.mkObj [("allPassed",toJson true),("transientFocus",describe native),
    ("sameTransientReads",toJson true),("fullOrderAndEvidenceChecked",toJson true),
    ("repairBound",toJson (32 : Nat)),("cancelledTaskJoined",toJson true),
    ("numericalClaimCancelled",toJson true),("externalExecutablePreserved",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") report.compress
  IO.println report.compress
end Eggshell.Research.BuiltinSearchChecks
