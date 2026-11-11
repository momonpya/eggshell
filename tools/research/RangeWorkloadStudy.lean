import tools.research.StudyLocal
open Lean StudyLocal
namespace RangeWorkloadStudy
def root := base/"range-workload"
def parent := base/"canonical-decoder-runtime"
def records := project/"docs/candidates/range-workload"

partial def linkProofImports (origin destination : System.FilePath) : IO Nat := do
  IO.FS.createDirAll destination
  let mut count := 0
  for entry in ← origin.readDir do
    let target := destination/entry.fileName
    if (← entry.path.symlinkMetadata).type == .dir then
      count := count+(← linkProofImports entry.path target)
    else if !(← target.pathExists) then
      let actual ← IO.FS.realPath entry.path
      discard <| command "/bin/ln" #["-s",actual.toString,target.toString]
      count := count+1
  return count

def prepareSelectorProofImports : IO Unit := do
  idle
  let count ← linkProofImports (root/"build/lib") (root/"selector-proof-lib")
  write (records/"selector-proof-imports.json") (Json.mkObj [("linkedExistingInterfaces",toJson count),
    ("copiedCompilerCacheBytes",toJson (0 : Nat)),("currentInputsUnchanged",toJson true)])

def auditSelectorConnection : IO Unit := do
  idle
  let destination := project/"tools/research/PreparedViewSelector.lean"
  let record := records/"selector-connection-resident-boundary.json"
  check (!(← record.pathExists)) "preserve prepared selector source audit"
  let handoff ← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")
  let (sealed,_) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (parent/"build/Eggshell_Handoff.source")))
  check (handoff == sealed) "selector source differs from current native producer"
  let start := "def selectView (query : ServiceQuery)"
  let ending := "/-- A generic-only query needs no service-owned original row."
  check ((handoff.splitOn start).length == 2 && (handoff.splitOn ending).length == 2)
    "source selector boundaries changed"
  let originalBody := start++((handoff.splitOn start)[1]!.splitOn ending)[0]!
  let one := fun (text before after : String) => do
    check ((text.splitOn before).length == 2) "selector seam differs from reviewed source"
    pure (text.replace before after)
  let expected ← one originalBody
    "def selectView (query : ServiceQuery) (units : Array ServiceUnit)\n    (pieces : List CuePiece) (source : Synapses.PreparedSourceView.Domain) : Option ServiceChoice := do\n  let p ← problemFromView query source units pieces\n"
    "def selectUsing (query : ServiceQuery) (units : Array ServiceUnit)\n    (pieces : List CuePiece) (source : Synapses.PreparedSourceView.Domain)\n    (build : Option SharedCoverage.Problem)\n    (makeRecipe : (directory : Array Nat × Array (Nat × Nat)) →\n      (p : SharedCoverage.Problem) → BundlePlan query.owners (units.map (·.shape)) → Option (ClosedCoverage.Recipe p)) :\n    Option ServiceChoice := do\n  let p ← build\n"
  let expected ← one expected
    "  let indexedPieces := pieces.zipIdx.toArray\n  let pieceIndex := PreparedCueIndex.prepare cueBucketKey indexedPieces\n  let recipe := bundleRecipeIndexed? keys shapes indexedPieces pieceIndex cueIndex p\n"
    "  let recipe := makeRecipe cueIndex p\n"
  let candidate ← IO.FS.readFile destination
  let first := "def selectUsing (query : ServiceQuery)"
  let last := "theorem recipe_function_exact"
  check ((candidate.splitOn first).length == 2 && (candidate.splitOn last).length == 2)
    "shared selector body boundaries changed"
  let actual := first++((candidate.splitOn first)[1]!.splitOn last)[0]!
  check (actual.trimAscii.toString == expected.trimAscii.toString) "selector control/body/diagnostic code changed outside two typed seams"
  let caller := root/"selector-source/Eggshell/PublicationService.lean"
  let (sealedCaller,_) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (parent/"build/Eggshell_PublicationService.source")))
  let expectedCaller ← one sealedCaller "public import Eggshell.Handoff\n"
    "public import Eggshell.Handoff\npublic import tools.research.PreparedViewSelector\n"
  check ((← IO.FS.readFile caller) == expectedCaller) "product caller changed outside proof import"
  let proof ← IO.FS.readFile (records/"selector-connection-proof.txt")
  check (!proof.contains "error:" && !proof.contains "sorryAx" &&
    proof.contains "reference_exact" && proof.contains "borrowed_recipes_exact" &&
    proof.contains "chooseWith_exact" && proof.contains "choose_exact" && proof.contains "selectView_compiled") "selector proof was not closed"
  write record (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("sourceSha256",toJson (← hash destination)),("sharedBodyMatchesOriginalOutsideTypedSeams",toJson true),
    ("originalControlCodeChanged",toJson false),("callerOnlyImportsProvedCompilerSubstitution",toJson true),
    ("proofSha256",toJson (← hash (records/"selector-connection-proof.txt"))),
    ("genericAndFileUnitsIncluded",toJson true),("pureEntireChoiceEqual",toJson true),
    ("geometryBuiltOncePerSelectionNotYetRetainedAcrossQueries",toJson true),
    ("borrowedEntryBuildsStructuralTrees",toJson false),("residentServiceConnected",toJson false),
    ("nativeCallTargetVerified",toJson false),("hookOrTokenImprovementMeasured",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])


def prepareSelectorNative : IO Unit := do
  idle
  let audit ← read (records/"selector-connection-resident-boundary.json")
  check (audit.getObjValD "pureEntireChoiceEqual" == toJson true &&
    audit.getObjValD "sourceSha256" == toJson (← hash (project/"tools/research/PreparedViewSelector.lean")) &&
    audit.getObjValD "parentRuntimeSha256" == toJson (← hash (parent/"build/StudyMain")))
    "selector or current parent changed since proof/source audit"
  let candidate := root/"selector"
  let settings := "range-selector-native-settings.json"
  check (!(← candidate.pathExists)) "preserve isolated selector candidate"
  materialize (parent/"build") (candidate/"source") (candidate/"build")
    "tools.research.OwnedSelectionRuntime" settings
  for name in ["FactoredIncidence","RangeIncidence","ProductRangeIncidence","PreparedSelectorIncidence","PreparedViewSelector"] do
    IO.FS.writeFile (candidate/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  IO.FS.writeFile (candidate/"source/Eggshell/PublicationService.lean")
    (← IO.FS.readFile (root/"selector-source/Eggshell/PublicationService.lean"))
  IO.FS.createDirAll (candidate/"prefix/libexec")
  discard <| command "/bin/ln" #["-s",(candidate/"build/StudyMain").toString,(candidate/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/ln" #["-s",(parent/"prefix/share").toString,(candidate/"prefix/share").toString]
  guard "range-selector-native-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/settings).toString]
  write (records/"selector-native-plan.json") (Json.mkObj [
    ("parentRuntimeSha256",audit.getObjValD "parentRuntimeSha256"),
    ("candidate",toJson candidate.toString),("settings",toJson (base/settings).toString),
    ("guardSettings",toJson (base/"range-selector-native-build.guard-settings.json").toString),
    ("guardStarted",toJson false),("requiredFreeKiB",toJson (2097152 : Nat)),
    ("maxRelatedRssKiB",toJson (4358524 : Nat)),("maximumClientsOnThisMac",toJson (16 : Nat)),
    ("changedProductSources",toJson #["Eggshell.PublicationService:proof import"]),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def main (args : List String) : IO Unit := do
  match args with
  | ["prepare-selector-proof-imports"] => prepareSelectorProofImports
  | ["audit-selector-connection"] => auditSelectorConnection
  | ["prepare-selector-native"] => prepareSelectorNative
  | ["show-summary"] => IO.println ((← read (records/"summary.json")).getObjValD "topics").compress
  | _ => throw (IO.userError "active range selector stage required")
end RangeWorkloadStudy
def main := RangeWorkloadStudy.main
