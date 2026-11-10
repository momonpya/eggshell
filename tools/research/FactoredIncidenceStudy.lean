import tools.research.StudyLocal
open Lean StudyLocal
namespace FactoredIncidenceStudy
def root := base/"factored-incidence"
def source := root/"source"
def build := root/"build"
def parent := base/"canonical-decoder-runtime"
def records := project/"docs/candidates/factored-incidence"
def driver := project/"tools/research/FactoredIncidenceStudy.lean"
def auditRange (destination : System.FilePath) : IO Unit := do
  IO.FS.createDirAll destination
  let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
    "inspect",build.toString,(destination/"native.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
    "component-sources",(parent/"build").toString,build.toString,(destination/"sources.json").toString,
    "Eggshell.Handoff","Eggshell.OrderedIncidence","Eggshell.HashDistinct"]
  for name in ["FactoredIncidence","RangeIncidence","ProductRangeIncidence","RangeIncidenceBench"] do
    let (actual,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/("tools_research_"++name++".source"))))
    check (actual == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty) "native range component source differs"
    if name == "RangeIncidence" || name == "ProductRangeIncidence" then
      let proof ← IO.FS.readFile (build/("tools_research_"++name++"-lean.stdout"))
      check (!proof.contains "sorryAx") "range bridge proof is not closed"
      IO.FS.writeFile (destination/(name++"-axioms.txt")) proof
  write (destination/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
    ("productChanges",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => do
    idle
    check (!(← root.pathExists) && !(← records.pathExists)) "preserve factored incidence evidence"
    IO.FS.createDirAll records
    materialize (parent/"build") source build "tools.research.FactoredIncidenceBench" "factored-incidence-settings.json"
    for name in ["FactoredIncidence","SharedIncidence"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    write (records/"plan.json") (Json.mkObj [("classificationPreviousTurn",toJson "progress:CPU demand measured;scope membership recomputation selected;no new pool/cache trial"),
      ("componentOnly",toJson true),("reference",toJson "family postings and prepared hash membership;full ordered outputs"),
      ("cases",toJson #["empty","small","balanced10637x17414","single-scope","dense","wide"]),
      ("order",toJson "AB,BA,AB"),("productConnection",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "factored-incidence-build-ready" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"factored-incidence-settings.json").toString]
  | ["rebuild",label] => do
    idle
    for name in ["FactoredIncidence","SharedIncidence","FactoredIncidenceBench"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    guard ("factored-incidence-"++label) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"factored-incidence-settings.json").toString]
  | ["audit"] => do
    discard <| finished "factored-incidence-build-ready"
    guard "factored-incidence-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"audit-worker"]
  | ["audit-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
      "inspect",build.toString,(records/"native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
      "component-sources",(parent/"build").toString,build.toString,(records/"sources.json").toString,
      "Eggshell.OrderedIncidence","Eggshell.HashDistinct"]
    for name in ["FactoredIncidence","FactoredIncidenceBench"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/("tools_research_"++name++".source"))))
      check (actual == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty) "native component source differs"
    let proof ← IO.FS.readFile (build/"tools_research_FactoredIncidence-lean.stdout")
    check (!proof.contains "sorryAx") "unclosed relation refinement"
    IO.FS.writeFile (records/"axioms.txt") proof
    write (records/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("productChanges",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  | ["measure"] => do
    discard <| finished "factored-incidence-audit"
    check ((← read (records/"runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "audited component changed"
    guard "factored-incidence-measure" #[(build/"StudyMain").toString,(records/"component.json").toString]
  | ["prepare-sharing"] => do
    idle
    discard <| finished "factored-incidence-measure"
    check ((← read (records/"runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "preserve original component runtime first"
    let inputs ← #["FactoredIncidence","FactoredIncidenceBench"].mapM fun name => do
      return (name,← read (build/("tools_research_"++name++".source")))
    write (records/"direct-tested-source.json") (toJson inputs)
    for name in ["FactoredIncidence","SharedIncidence","FactoredIncidenceBench"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    write (records/"sharing-plan.json") (Json.mkObj [("reason",toJson "dense/wide direct incidence repeats identical ordered outputs across128 units;share exact structural coverage classes"),
      ("noQuestionSpecificRule",toJson true),("sameSixDatasets",toJson true),("order",toJson "ABC,CBA,ABC"),
      ("productConnection",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "factored-incidence-sharing-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"factored-incidence-settings.json").toString]
  | ["audit-sharing"] => do
    discard <| finished "factored-incidence-sharing-membership"
    guard "factored-incidence-sharing-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"audit-sharing-worker"]
  | ["audit-sharing-worker"] => do
    IO.FS.createDirAll (records/"sharing")
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
      "inspect",build.toString,(records/"sharing/native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
      "component-sources",(parent/"build").toString,build.toString,(records/"sharing/sources.json").toString,
      "Eggshell.OrderedIncidence","Eggshell.HashDistinct"]
    for name in ["FactoredIncidence","SharedIncidence","FactoredIncidenceBench"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/("tools_research_"++name++".source"))))
      check (actual == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty) "native grouped source differs"
      if name != "FactoredIncidenceBench" then
        let proof ← IO.FS.readFile (build/("tools_research_"++name++"-lean.stdout"))
        check (!proof.contains "sorryAx") "grouped relation proof is not closed"
        IO.FS.writeFile (records/"sharing"/(name++"-axioms.txt")) proof
    write (records/"sharing/runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("productChanges",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  | ["measure-sharing"] => do
    discard <| finished "factored-incidence-sharing-audit"
    check ((← read (records/"sharing/runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "audited grouped component changed"
    guard "factored-incidence-sharing-measure" #[(build/"StudyMain").toString,"shared",(records/"shared-component.json").toString]
  | ["collect"] => do
    idle
    let first ← finished "factored-incidence-measure"
    let second ← finished "factored-incidence-sharing-measure"
    for monitor in #[first,second] do
      check (monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "reason" == Json.null) "component resource stop"
    let direct ← read (records/"component.json")
    let shared ← read (records/"shared-component.json")
    let cases ← IO.ofExcept (shared.getObjValAs? (Array Json) "cases")
    check (cases.size == 6 && shared.getObjValD "controls" == toJson (9 : Nat)) "grouped component cases or controls missing"
    for entry in cases do
      let trials ← IO.ofExcept (entry.getObjValAs? (Array Json) "trials")
      check (trials.size == 3 && trials.all (fun row => row.getObjValD "allOrderedRowsEqual" == toJson true)) "ordered result changed"
    check (direct.getObjValD "controls" == toJson (8 : Nat) && shared.getObjValD "actualProductContainmentRefinementClosed" == toJson false) "incorrect validation boundary"
    write (records/"runs.json") (Json.mkObj [("direct",first),("shared",second),
      ("sameSixSyntheticDatasets",toJson true),("productContainmentAndScopeBridgeComplete",toJson false),
      ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["prepare-range"] => do
    idle
    check (← (records/"trimmed.json").pathExists) "retire ended finite-catalogue executable first"
    check (!(← (records/"range-plan.json").pathExists)) "preserve range plan"
    for name in ["FactoredIncidence","RangeIncidence","ProductRangeIncidence","RangeIncidenceBench"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    let settings := (← read (base/"factored-incidence-settings.json")).setObjVal! "mainModule" (toJson "tools.research.RangeIncidenceBench")
    write (base/"factored-incidence-range-settings.json") settings
    write (records/"range-plan.json") (Json.mkObj [("reason",toJson "finite catalogue membership cannot justify arbitrary future spans;exact scoped interval resolver and full geometry quotient"),
      ("originalProductPredicates",toJson #["problemFromView:single raw range","UnitShape.coversPrepared:union"]),
      ("queryEndpointsNotPublished",toJson true),("sameSixSyntheticShapes",toJson true),
      ("order",toJson "AB,BA,AB"),("productConnection",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "factored-incidence-range-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"factored-incidence-range-settings.json").toString]
  | ["audit-range"] => do
    discard <| finished "factored-incidence-range-build"
    guard "factored-incidence-range-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"audit-range-worker"]
  | ["audit-range-worker"] => auditRange (records/"range")
  | ["audit-range-final-worker"] => auditRange (records/"range/final")
  | ["measure-range"] => do
    discard <| finished "factored-incidence-range-audit"
    check ((← read (records/"range/runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "audited range component changed"
    guard "factored-incidence-range-measure" #[(build/"StudyMain").toString,(records/"range-component.json").toString]
  | ["close-range-controls"] => do
    idle
    discard <| finished "factored-incidence-range-measure"
    check ((← read (records/"range/runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "preserve initial range executable evidence"
    let names := #["FactoredIncidence","RangeIncidence","ProductRangeIncidence","RangeIncidenceBench"]
    let sources ← names.mapM fun name => do
      return (name,← read (build/("tools_research_"++name++".source")))
    write (records/"range/initial-tested-source.json") (toJson sources)
    IO.FS.writeFile (source/"tools/research/RangeIncidenceBench.lean") (← IO.FS.readFile (project/"tools/research/RangeIncidenceBench.lean"))
    write (records/"range/control-correction.json") (Json.mkObj [
      ("reason",toJson "initial local constant-hash instances did not reach monomorphic helpers;pass dictionaries explicitly to exercise collisions"),
      ("algorithmAndFixtureUnchanged",toJson true),("initialRunNotClaimedAsCollisionInjection",toJson true)])
    guard "factored-incidence-range-control-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"factored-incidence-range-settings.json").toString]
  | ["audit-range-controls"] => do
    discard <| finished "factored-incidence-range-control-build"
    guard "factored-incidence-range-closed-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"audit-range-final-worker"]
  | ["measure-range-controls"] => do
    discard <| finished "factored-incidence-range-closed-audit"
    check ((← read (records/"range/final/runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "audited corrected range component changed"
    guard "factored-incidence-range-control-measure" #[(build/"StudyMain").toString,(records/"range-corrected-component.json").toString]
  | ["collect-range"] => do
    idle
    let final ← finished "factored-incidence-range-control-measure"
    check (final.getObjValD "guardTriggered" == toJson false && final.getObjValD "reason" == Json.null) "range measurement resource stop"
    let result ← read (records/"range-corrected-component.json")
    let cases ← IO.ofExcept (result.getObjValAs? (Array Json) "cases")
    check (cases.size == 6 && result.getObjValD "controlComparisons" == toJson (6 : Nat)) "range controls incomplete"
    for entry in cases do
      let trials ← IO.ofExcept (entry.getObjValAs? (Array Json) "trials")
      check (trials.size == 3 && trials.all (fun row => row.getObjValD "allOrderedRowsEqual" == toJson true)) "range ordered output changed"
    let mut resources := #[]
    for entry in ← base.readDir do
      if !entry.fileName.startsWith "factored-incidence-" || !entry.fileName.endsWith ".guard.json" then continue
      let monitor ← read entry.path
      check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "range work still owns a process"
      resources := resources.push (entry.fileName,monitor)
    write (records/"range/resources.json") (toJson resources)
    write (records/"range/runs.json") (Json.mkObj [("final",final),("sameSixSyntheticShapes",toJson true),
      ("arbitraryCoordinateAndProductPredicateProofs",toJson true),("wholeProductProblemAndBundleRefinementClosed",toJson false),
      ("publicationAndQueryScopeBridgeComplete",toJson false),("actualHookCalls",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["trim-range"] => do
    idle
    check (← (records/"range/runs.json").pathExists) "collect range measurement first"
    discard <| finished "factored-incidence-range-control-measure"
    check ((← read (records/"range/final/runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "ended range executable changed"
    let paths := #[parent/"build/StudyMain",base/"current-six/stable-source-rows/build/StudyMain",
      base/"current-six/fixed-sequence/controller-build/StudyMain",base/"snapshot-scheduling/work/work.egg/head"]
    let hashes ← paths.mapM hash
    let executable := build/"StudyMain"
    let bytes := (← executable.metadata).byteSize.toNat
    IO.FS.removeFile executable
    let probe := source/"RangeImportProbe.lean"
    if ← probe.pathExists then IO.FS.removeFile probe
    check ((← paths.mapM hash) == hashes) "range cleanup changed current runtime or source head"
    write (records/"range/trimmed.json") (Json.mkObj [("logicalBytes",toJson bytes),("archive",toJson false),
      ("removedExecutable",toJson executable.toString),("importProbeRemoved",toJson true),
      ("nativeInputsRetainedForProductConnection",toJson true),("protectedHashesUnchanged",toJson true)])
  | ["trim"] => do
    idle
    check (← (records/"runs.json").pathExists) "collect completed component first"
    check ((← read (records/"sharing/runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "completed runtime changed"
    let paths := #[parent/"build/StudyMain",base/"current-six/stable-source-rows/build/StudyMain",
      base/"current-six/fixed-sequence/controller-build/StudyMain",base/"snapshot-scheduling/work/work.egg/head"]
    let hashes ← paths.mapM hash
    let mut resources := #[]
    for entry in ← base.readDir do
      if !entry.fileName.startsWith "factored-incidence-" || !entry.fileName.endsWith ".guard.json" then continue
      let monitor ← read entry.path
      check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component still owns a process"
      resources := resources.push (entry.fileName,monitor)
    write (records/"resources.json") (toJson resources)
    let executable := build/"StudyMain"
    let bytes := (← executable.metadata).byteSize.toNat
    IO.FS.removeFile executable
    check ((← paths.mapM hash) == hashes) "trimming changed current runtime or original head"
    write (records/"trimmed.json") (Json.mkObj [("removedExecutable",toJson executable.toString),
      ("logicalBytes",toJson bytes),("archive",toJson false),
      ("kernelObjectsAndInterfacesRetainedForProductRefinement",toJson true),
      ("sourceCopyRetainedForNextNativeBuild",toJson true),("protectedHashesUnchanged",toJson true)])
  | _ => throw (IO.userError "factored incidence:setup|rebuild LABEL|audit|measure|prepare-sharing|audit-sharing|measure-sharing|collect|trim|prepare-range|audit-range|measure-range|close-range-controls|audit-range-controls|measure-range-controls|collect-range|trim-range")
end FactoredIncidenceStudy
def main := FactoredIncidenceStudy.main
