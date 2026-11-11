import tools.research.StudyLocal
open Lean StudyLocal
namespace RangeWorkloadStudy
def root := base/"range-workload"
def parent := base/"canonical-decoder-runtime"
def records := project/"docs/candidates/range-workload"

def auditSelectorConnection : IO Unit := do
  idle
  let destination := project/"tools/research/PreparedViewSelector.lean"
  let record := records/"query-preparation-connection.json"
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
  let caller := root/"selector/source/Eggshell/PublicationService.lean"
  let (sealedCaller,_) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (parent/"build/Eggshell_PublicationService.source")))
  let expectedCaller ← one sealedCaller "public import Eggshell.Handoff\n"
    "public import Eggshell.Handoff\npublic import tools.research.PreparedViewSelector\n"
  check ((← IO.FS.readFile caller) == expectedCaller) "product caller changed outside proof import"
  let proof ← IO.FS.readFile (records/"query-preparation-proof.txt")
  check (!proof.contains "error:" && !proof.contains "sorryAx" &&
    proof.contains "reference_exact" && proof.contains "borrowed_recipes_exact" &&
    proof.contains "chooseWith_exact" && proof.contains "choose_exact" && proof.contains "selectView_compiled") "selector proof was not closed"
  write record (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("sourceSha256",toJson (← hash destination)),("sharedBodyMatchesOriginalOutsideTypedSeams",toJson true),
    ("originalControlCodeChanged",toJson false),("callerOnlyImportsProvedCompilerSubstitution",toJson true),
    ("proofSha256",toJson (← hash (records/"query-preparation-proof.txt"))),
    ("genericAndFileUnitsIncluded",toJson true),("pureEntireChoiceEqual",toJson true),
    ("geometryBuiltOncePerSelectionNotYetRetainedAcrossQueries",toJson true),
    ("borrowedEntryBuildsStructuralTrees",toJson false),("residentServiceConnected",toJson false),
    ("nativeCallTargetVerified",toJson false),("hookOrTokenImprovementMeasured",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])


def auditNative : IO Unit := do
  idle
  discard <| finished "range-selector-query-preparation-build"
  let candidate := root/"selector"
  let auditor := #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]
  discard <| command "/usr/bin/env" (auditor++#["inspect",(candidate/"build").toString,
    (records/"query-preparation-native.json").toString])
  discard <| command "/usr/bin/env" (auditor++#["compare-sources",(parent/"build").toString,
    (candidate/"build").toString,(records/"query-preparation-sources.json").toString,
    "Eggshell.PublicationService","+tools.research.FactoredIncidence","+tools.research.RangeIncidence",
    "+tools.research.ProductRangeIncidence","+tools.research.PreparedSelectorIncidence",
    "+tools.research.PreparedViewSelector"])
  for name in ["FactoredIncidence","RangeIncidence","ProductRangeIncidence","PreparedSelectorIncidence","PreparedViewSelector"] do
    let (sealed,_) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read (candidate/"build"/("tools_research_"++name++".source"))))
    check (sealed == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))))
      "native helper source differs from current proved source"
  auditSelectorConnection

def prepareCapacity (label : String) (origin : System.FilePath) (diagnostic : Bool) : IO Unit := do
  let output := root/"selector"/label
  let runtime := origin/"prefix/libexec/eggshell"
  let config := output/"config.toml"
  let reference ← read (parent/"preflight-input.json")
  let environments : Array (String × Option String) ← IO.ofExcept
    (fromJson? (reference.getObjValD "environment"))
  let environments := environments.map fun (key,value) => (key,
    if key == "EGGSHELL_PREFIX" then some (origin/"prefix").toString
    else if key == "PLUGIN_ROOT" then some (origin/"prefix/share/eggshell/codex-plugin").toString
    else if key == "EGGSHELL_CONFIG" then some config.toString else value)
  let input := Json.mkObj ((← IO.ofExcept reference.getObj?).toArray.toList.filter (fun row =>
    !["output","runtime","runtimeSha256","plugin","config","environment","counts","diagnostic"].contains row.1)++[
    ("output",toJson output.toString),("runtime",toJson runtime.toString),
    ("runtimeSha256",toJson (← hash runtime)),("plugin",toJson (origin/"prefix/share/eggshell/codex-plugin").toString),
    ("config",toJson config.toString),("environment",toJson environments),
    ("counts",toJson (if diagnostic then #[(4 : Nat)] else #[4,16])),("diagnostic",toJson diagnostic)])
  let path := root/"selector"/(label++"-input.json")
  check (!(← path.pathExists) && !(← output.pathExists)) "preserve capacity observation"
  write path input
  let unsets := environments.foldl (fun args (key,value) =>
    if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environments.filterMap fun (key,value) => value.map (key++"="++·)
  guard ("range-selector-"++label) (#["/usr/bin/env"]++unsets++assignments++
    #[runtime.toString,"owned-selection-capacity",path.toString])

def preparePreflight : IO Unit := do
  idle
  discard <| finished "range-selector-query-preparation-build"
  check ((← read (records/"query-preparation-native.json")).getObjValD "consistent" == toJson true &&
    (← read (records/"query-preparation-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "native closure/source audit required before hook preflight"
  prepareCapacity "preflight-cache-recovered" (root/"selector") true

def prepareComparison : IO Unit := do
  idle
  discard <| finished "range-selector-preflight-cache-recovered"
  let evidence ← read (root/"selector/preflight-cache-recovered/phase-4/result.json")
  check (evidence.getObjValD "passed" == toJson true) "preflight did not preserve bodies/ACK/search"
  for (label,origin) in [("a-first",parent),("b-first",root/"selector"),
      ("b-second",root/"selector"),("a-second",parent)] do
    prepareCapacity label origin false
  write (records/"query-preparation-comparison-plan.json") (Json.mkObj [
    ("order",toJson #["a-first","b-first","b-second","a-second"]),
    ("countsPerArm",toJson (#[(4 : Nat),16])),("maximumClientsOnThisMac",toJson (16 : Nat)),
    ("sameSourceBodiesQuestionsAndHarness",toJson true),("data",(← read (parent/"preflight-input.json")).getObjValD "data"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

/-- Collect the actual published bytes before retiring duplicate client state.
This controller reads evidence files only; product DB access stays native. -/
def collectComparison : IO Unit := do
  idle
  let destination := records/"query-preparation-comparison.json"
  check (!(← destination.pathExists)) "preserve completed comparison"
  let mut arms := #[]
  let mut verified := 0
  let mut allPassed := true
  for label in ["a-first","b-first","b-second","a-second"] do
    let monitor ← read (base/("range-selector-"++label++".guard.json"))
    check (monitor.getObjValD "state" == toJson "finished" &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "comparison still owns native processes"
    let completed := monitor.getObjValD "exitCode" == toJson (0 : Nat)
    allPassed := allPassed && completed
    let directory := root/"selector"/label
    let input ← read (root/"selector"/(label++"-input.json"))
    if completed then
      let report ← read (directory/"report.json")
      check (report.getObjValD "allPhasesPassed" == toJson true &&
        report.getObjValD "originalSourceFilesUnchanged" == toJson true &&
        report.getObjValD "runtimeSha256" == input.getObjValD "runtimeSha256") "successful guard lacks frozen workload evidence"
    let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
    let topics ← IO.ofExcept ((input.getObjValD "topics").getArr?)
    let verify := fun (rows : Array Json) (clientRoot : System.FilePath) => do
      let mut witnesses := #[]
      for row in rows do
        let id ← IO.ofExcept (row.getObjValAs? Nat "client")
        let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
        let some spec := topics.find? (fun spec => spec.getObjValD "topic" == toJson topic) |
          throw (IO.userError "unknown delivered topic")
        let body : System.FilePath := .mk (← IO.ofExcept (spec.getObjValAs? String "body"))
        let stdout := clientRoot/s!"client-{id}/stdout"
        let parsed ← read stdout
        check ((parsed.getObjValD "hookSpecificOutput").getObjValD "additionalContext" ==
          toJson (← IO.FS.readFile body)) "actual stdout differs from frozen canonical body"
        let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
        let received := data/"receipts"/receipt
        let published := (← read (received/"published.json")).getObjValD "data"
        check (published.getObjValD "sha256" == toJson (← hash stdout)) "stdout differs from publication receipt"
        let search := (← read (received/"search.json")).getObjValD "data"
        let trace := search.getObjValD "trace"
        let synapses := (← read (received/"synaptic-delivery.json")).getObjValD "data"
        check (trace.getObjValD "route" == toJson "configured" && trace.getObjValD "semantic" == toJson "completed" &&
          synapses.getObjValD "complete" == toJson true && synapses.getObjValD "packetVerified" == toJson true &&
          row.getObjValD "acknowledged" == toJson true && row.getObjValD "success" == toJson true)
          "published client lacks complete semantic/synapse/ACK evidence"
        witnesses := witnesses.push (Json.mkObj [("client",toJson id),("topic",toJson topic),
          ("stdoutSha256",published.getObjValD "sha256"),("bodySha256",spec.getObjValD "sha256"),
          ("elapsedMs",row.getObjValD "elapsedMs"),("receipt",toJson receipt)])
      return witnesses
    let primeRows ← if ← (directory/"prime.json").pathExists then
        IO.ofExcept (fromJson? (← read (directory/"prime.json"))) else pure (#[] : Array Json)
    let primes ← verify primeRows (directory/"prime")
    let mut phases := #[]
    for count in [4,16] do
      let phase := directory/s!"phase-{count}"
      let result ← if ← (phase/"result.json").pathExists then read (phase/"result.json") else pure Json.null
      let mut observed := #[]
      let mut missing := #[]
      for id in [:count] do
        let path := phase/s!"client-{id}/result.json"
        if ← path.pathExists then observed := observed.push (← read path)
        else missing := missing.push id
      let successful := observed.filter (fun row => row.getObjValD "success" == toJson true)
      let witnesses ← verify successful phase
      verified := verified+witnesses.size
      phases := phases.push (Json.mkObj [("clients",toJson count),("wallMs",result.getObjValD "wallMs"),
        ("passed",toJson (result.getObjValD "passed" == toJson true)),("published",toJson witnesses),
        ("missingClientResults",toJson missing),("failedClients",toJson (observed.filter fun row => row.getObjValD "success" != toJson true))])
    verified := verified+primes.size
    arms := arms.push (Json.mkObj [("label",toJson label),("runtimeSha256",input.getObjValD "runtimeSha256"),
      ("inputSha256",toJson (← hash (root/"selector"/(label++"-input.json")))),
      ("guard",monitor),("primes",toJson primes),("phases",toJson phases)])
  write destination (Json.mkObj [("order",toJson #["a-first","b-first","b-second","a-second"]),
    ("verifiedPublishedClients",toJson verified),("verifiedClientsCanonicalSemanticSynapseAndAck",toJson true),
    ("allPlannedPhasesCompleted",toJson allPassed),("arms",toJson arms),("geometryResidentAcrossQueries",toJson false),
    ("eightHourOrGrowingProjectValidation",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("paidMatchedComparisons",toJson (0 : Nat)),("adopted",toJson false)])

def main (args : List String) : IO Unit := do
  match args with
  | ["audit-native"] => auditNative
  | ["prepare-preflight"] => preparePreflight
  | ["prepare-comparison"] => prepareComparison
  | ["collect-comparison"] => collectComparison
  | ["show-summary"] => IO.println ((← read (records/"summary.json")).getObjValD "topics").compress
  | _ => throw (IO.userError "active range selector stage required")
end RangeWorkloadStudy
def main := RangeWorkloadStudy.main
