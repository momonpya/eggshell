import tools.research.StudyLocal
open Lean StudyLocal
namespace ParentFactsStudy
def parent := base/"canonical-decoder-runtime"
def root := base/"parent-facts"
def source := root/"source"
def build := root/"build"
def records := project/"docs/candidates/parent-facts"
def requireCompilerSpace : IO Unit := do
  let available := ((← command "/bin/df" #["-Pk",base.toString]).splitOn "\n")[1]!
    |>.splitOn " " |>.filter (!·.isEmpty)
  check ((available[3]!.toNat?.getD 0) ≥ 3145728)
    "need 3 GiB free for private compiler outputs and native linking"
def replace (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) "nonunique actual source replacement"
  return text.replace before after

def cloneArtifacts : IO Unit := do
  IO.FS.createDirAll (build/"lib")
  let manifest ← read (parent/"build/build.json")
  for row in ← IO.ofExcept (manifest.getObjValAs? (Array Json) "modules") do
    let name ← IO.ofExcept (row.getObjValAs? String "module")
    let interface := parent/"build/lib"/(name.replace "." "/"++".olean")
    if !(← interface.pathExists) || (← interface.symlinkMetadata).type != .file then continue
    let clone := fun (origin target : System.FilePath) => do
      IO.FS.createDirAll target.parent.get!
      check (!(← target.pathExists)) "preserve private compiler output"
      discard <| command "/bin/cp" #["-c",origin.toString,target.toString]
      check ((← IO.FS.readBinFile origin) == (← IO.FS.readBinFile target)) "compiler clone differs"
    for extension in ["o","source","dependencies"] do
      let file := name.replace "." "_"++"."++extension
      clone (parent/"build"/file) (build/file)
    let moduleName := (name.splitOn ".").getLast!
    for entry in ← interface.parent.get!.readDir do
      if entry.fileName.startsWith (moduleName++".") && (← entry.path.symlinkMetadata).type == .file then
        clone entry.path ((build/"lib"/(name.replace "." "/")).parent.get! /entry.fileName)

def prepare : IO Unit := do
  idle
  requireCompilerSpace
  check (!(← root.pathExists)) "fresh candidate required"
  check ((← hash (parent/"build/StudyMain")) ==
    "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab") "parent changed"
  IO.FS.createDirAll records
  materialize (parent/"build") source build "tools.research.ParentFactsRuntime" "parent-facts-build-settings.json"
  cloneArtifacts
  let original ← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")
  let links ← IO.FS.readFile (project/"tools/research/PreparedCitationLinks.lean")
  let [_,links] := links.splitOn "namespace Eggshell.Plugin.PreparedCitationLinks\n" |
    throw (IO.userError "missing existing parsed-link proof")
  let [links,_] := links.splitOn "end Eggshell.Plugin.PreparedCitationLinks" |
    throw (IO.userError "missing parsed-link namespace end")
  let parser := "namespace PreparedCitationLinks\n"++links++"end PreparedCitationLinks\n\n"
  let text ← replace original "def observedLineNumber? (text : String)" (parser++"def observedLineNumber? (text : String)")
  let text ← replace text "public import Eggshell.SourcePlan\n"
    "public import Eggshell.SourcePlan\npublic import Std.Data.HashMap.Lemmas\n"
  let [_,ranked] := original.splitOn "def rankedCitedObservationCoordinates (texts" |
    throw (IO.userError "original ranked citation function changed")
  let [ranked,_] := ranked.splitOn "\ndef citedObservationWindows" |
    throw (IO.userError "original ranked citation boundary changed")
  let ranked := "def rankedCitedObservationCoordinates (texts"++ranked
  let variant := ranked.replace "def rankedCitedObservationCoordinates (texts"
    "def rankedCitedObservationCoordinatesUsing (parse : Nat → String → String → List (Nat × Nat))\n    (texts"
    |>.replace "citedLineIntervals parent file.relative" "parse priority parent file.relative"
  let proof := "theorem ranked_citation_parser_exact\n"++
    "    (parse : Nat → String → String → List (Nat × Nat))\n"++
    "    (same : ∀ rank text relative,parse rank text relative = citedLineIntervals text relative)\n"++
    "    (texts : List (Nat × String)) (owner : OutcomeEdge) (records : List SourceEvidence.Record) :\n"++
    "    rankedCitedObservationCoordinatesUsing parse texts owner records = rankedCitedObservationCoordinates texts owner records := by\n"++
    "  have exactParser : parse = fun _ => citedLineIntervals := by funext rank text relative; exact same rank text relative\n"++
    "  subst parse\n  rfl\n\n"++
    "theorem ranked_prepared_parser_exact (parents texts : List (Nat × String))\n"++
    "    (owner : OutcomeEdge) (records : List SourceEvidence.Record) :\n"++
    "    rankedCitedObservationCoordinatesUsing (PreparedCitationLinks.Parser.prepare parents).parse texts owner records =\n"++
    "      rankedCitedObservationCoordinates texts owner records :=\n"++
    "  ranked_citation_parser_exact _ (PreparedCitationLinks.Parser.parse_exact _ (PreparedCitationLinks.Parser.prepared_valid parents)) ..\n"++
    "#print axioms ranked_prepared_parser_exact\n\n"
  let text ← replace text "\ndef citedObservationWindows" ("\n"++variant++proof++"def citedObservationWindows")
  let facts := "namespace SourceCitationFacts\n"++
    "def prepare (index : SourceIncidence all unions) (parents : List (Nat × Value × String)) : List (Nat × List Value × String) :=\n"++
    "  parents.map fun (rank,work,text) => (rank,(index.neighborhood [work]).map (·.work),text)\n"++
    "def admitted (facts : List (Nat × List Value × String)) (work : Value) : List (Nat × String) :=\n"++
    "  facts.filterMap fun (rank,reached,text) => if reached.any (· == work) then some (rank,text) else none\n"++
    "theorem admitted_exact (index : SourceIncidence all unions) (parents : List (Nat × Value × String)) (work : Value) :\n"++
    "    admitted (prepare index parents) work = (parents.filterMap fun (rank,parent,text) =>\n"++
    "      if (index.neighborhood [parent]).any (·.work == work) then some (rank,text) else none) := by\n"++
    "  unfold admitted prepare\n  rw [List.filterMap_map]\n"++
    "  apply congrArg (fun f => parents.filterMap f)\n  funext row\n  rcases row with ⟨rank,parent,text⟩\n"++
    "  simp only [Function.comp_apply,List.any_map]\n  rfl\n"++
    "#print axioms admitted_exact\nend SourceCitationFacts\n\n"
  let text ← replace text "def citedObservationWindows" (facts++"def citedObservationWindows")
  let text ← replace text "    let referenced := if evidence.isSome then [] else focusDomain.filterMap fun item =>\n"
    ("    let queryParents := if evidence.isNone then parents else []\n"++
     "    let parentParser := PreparedCitationLinks.Parser.prepare (queryParents.map fun (rank,_,text) => (rank,text))\n"++
     "    let parentFacts := SourceCitationFacts.prepare sourceIncidence queryParents\n"++
     "    let referenced := if evidence.isSome then [] else focusDomain.filterMap fun item =>\n")
  let text ← replace text ("      let admitted := parents.filterMap fun (rank,work,text) =>\n"++
    "        if (sourceIncidence.neighborhood [work]).any (·.work == item.owner.work) then\n"++
    "          some (rank,text) else none\n")
    "      let admitted := SourceCitationFacts.admitted parentFacts item.owner.work\n"
  let text ← replace text "        rankedCitedObservationCoordinates admitted item.owner item.provenance).map"
    "        rankedCitedObservationCoordinatesUsing parentParser.parse admitted item.owner item.provenance).map"
  IO.FS.writeFile (source/"Eggshell/Handoff.lean") text
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/Handoff.lean",
    "--label","b/Eggshell/Handoff.lean",(parent/"source/Eggshell/Handoff.lean").toString,(source/"Eggshell/Handoff.lean").toString]}
  check (patch.exitCode == 1) "candidate patch absent"
  IO.FS.writeFile (records/"Handoff.patch") patch.stdout
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("productsChanged",toJson #["Eggshell.Handoff"]),("newPersistentCache",toJson false),
    ("newWireMetadata",toJson false),("indicesOrRankingWeightsChanged",toJson false),
    ("nativeGateCounts",toJson (#[(4 : Nat),16])),("continueOnlyIf16WaveMsBelow",toJson (11000 : Nat)),
    ("diagnosticNotAdoption",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "parent-facts-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"parent-facts-build-settings.json").toString]

/-- A changed Handoff forces these modules to rebuild. Their privately
cloned old outputs cannot be cache hits and need not coexist with replacements. -/
def pruneChangedClones : IO Unit := do
  idle
  check (!(← (base/"parent-facts-build.guard.json").pathExists)) "do not prune a started build"
  check (!(← (records/"pruned-changed-clones.json").pathExists)) "preserve clone retirement"
  let manifest ← read (parent/"build/build.json")
  let mut removed := #[]
  for row in ← IO.ofExcept (manifest.getObjValAs? (Array Json) "modules") do
    let name ← IO.ofExcept (row.getObjValAs? String "module")
    let stem := name.replace "." "_"
    let dependencies := build/(stem++".dependencies")
    if !(← dependencies.pathExists) then continue
    let closure : Array (String × String) ← IO.ofExcept (fromJson? (← read dependencies))
    if !closure.any (·.1 == "Eggshell.Handoff") then continue
    for extension in ["o","source","dependencies"] do
      let file := stem++"."++extension
      let target := build/file
      check ((← target.symlinkMetadata).type == IO.FS.FileType.file &&
        (← IO.FS.readBinFile target) == (← IO.FS.readBinFile (parent/"build"/file)))
        "clone is not an unchanged private old compiler artifact"
      removed := removed.push (target.toString,(← target.metadata).byteSize.toNat)
      IO.FS.removeFile target
    let interface := build/"lib"/(name.replace "." "/"++".olean")
    let moduleName := (name.splitOn ".").getLast!
    for entry in ← interface.parent.get!.readDir do
      if entry.fileName.startsWith (moduleName++".") && (← entry.path.symlinkMetadata).type == IO.FS.FileType.file then
        let reference := (parent/"build/lib"/(name.replace "." "/")).parent.get! /entry.fileName
        check ((← IO.FS.readBinFile entry.path) == (← IO.FS.readBinFile reference)) "private interface clone changed"
        removed := removed.push (entry.path.toString,(← entry.path.metadata).byteSize.toNat)
        IO.FS.removeFile entry.path
  write (records/"pruned-changed-clones.json") (Json.mkObj [("removed",toJson removed),
    ("parentUnchanged",toJson ((← hash (parent/"build/StudyMain")) ==
      "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab")),
    ("nativeBuildsStarted",toJson (0 : Nat)),("archive",toJson false)])

def prepareProof : IO Unit := do
  idle
  guard "parent-facts-proof" #["/usr/bin/env","LEAN_PATH="++(parent/"build/lib").toString,
    (compiler/"bin/lean").toString,"--root="++source.toString,"-j1","-M3072","-DwarningAsError=true",
    (source/"Eggshell/Handoff.lean").toString]

def repairProof : IO Unit := do
  idle
  let failed ← read (base/"parent-facts-proof.guard.json")
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "exitCode" == toJson (1 : Nat) &&
    failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "first proof has not failed and drained"
  let path := source/"Eggshell/Handoff.lean"
  let text ← replace (← IO.FS.readFile path)
    "  simp only [admitted,prepare,List.filterMap_map,List.any_map]\n  rfl\n"
    ("  unfold admitted prepare\n  rw [List.filterMap_map]\n"++
     "  apply congrArg (fun f => parents.filterMap f)\n  funext row\n  rcases row with ⟨rank,parent,text⟩\n"++
     "  simp only [Function.comp_apply,List.any_map]\n")
  write (records/"proof-first-rejected.json") (Json.mkObj [("guard",failed),
    ("compilerOutput",toJson (← IO.FS.readFile (base/"parent-facts-proof.stdout"))),
    ("nativeBuildsStarted",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  IO.FS.writeFile path text
  guard "parent-facts-proof2" #["/usr/bin/env","LEAN_PATH="++(parent/"build/lib").toString,
    (compiler/"bin/lean").toString,"--root="++source.toString,"-j1","-M3072","-DwarningAsError=true",
    path.toString]

def finishProof : IO Unit := do
  idle
  let failed ← read (base/"parent-facts-proof2.guard.json")
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "exitCode" == toJson (1 : Nat) &&
    failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "second proof has not failed and drained"
  let path := source/"Eggshell/Handoff.lean"
  let text ← replace (← IO.FS.readFile path)
    "  simp only [Function.comp_apply,List.any_map]\n#print axioms admitted_exact"
    "  simp only [Function.comp_apply,List.any_map]\n  rfl\n#print axioms admitted_exact"
  write (records/"proof-second-rejected.json") (Json.mkObj [("guard",failed),
    ("compilerOutput",toJson (← IO.FS.readFile (base/"parent-facts-proof2.stdout"))),
    ("nativeBuildsStarted",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  IO.FS.writeFile path text
  guard "parent-facts-proof3" #["/usr/bin/env","LEAN_PATH="++(parent/"build/lib").toString,
    (compiler/"bin/lean").toString,"--root="++source.toString,"-j1","-M3072","-DwarningAsError=true",
    path.toString]

def collectProof : IO Unit := do
  idle
  let proof ← finished "parent-facts-proof3"
  let log ← IO.FS.readFile (base/"parent-facts-proof3.stdout")
  check (!log.contains "sorryAx" && !log.contains "error:" && !log.contains "warning:") "proof did not close cleanly"
  IO.FS.writeFile (records/"proof.txt") log
  let path := source/"Eggshell/Handoff.lean"
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/Handoff.lean",
    "--label","b/Eggshell/Handoff.lean",(parent/"source/Eggshell/Handoff.lean").toString,path.toString]}
  check (patch.exitCode == 1) "candidate difference missing"
  IO.FS.writeFile (records/"Handoff.patch") patch.stdout
  let free ← command "/bin/df" #["-Pk",base.toString]
  write (records/"proof-result.json") (Json.mkObj [("guard",proof),
    ("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("candidateHandoffSourceSha256",toJson (← hash path)),("freeSpaceObservation",toJson free),
    ("nativeBuildsStarted",toJson (0 : Nat)),("candidateHookCalls",toJson (0 : Nat)),
    ("speedupVerified",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let prior ← read (base/"citation-gate-parent-retirement-input.json")
  let config := prior.setObjVal! "closedDirectories" (toJson #[(root/"build").toString])
    |>.setObjVal! "plan" (toJson (base/"parent-facts-old-clones-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"old-clones-retirement.json").toString)
  write (base/"parent-facts-old-clones-retirement-input.json") config

def resumeCache : IO Unit := do
  idle
  check (!(← build.pathExists) && !(← (base/"parent-facts-build.guard.json").pathExists))
    "only the never-started candidate build can restore its private cache"
  let record ← read (records/"proof-result.json")
  check (record.getObjValD "candidateHandoffSourceSha256" == toJson (← hash (source/"Eggshell/Handoff.lean")))
    "source changed since kernel validation"
  requireCompilerSpace
  cloneArtifacts

def prepareRun (baseline : Bool) : IO Unit := do
  idle
  let area := root/(if baseline then "baseline-cleanup" else "hooks")
  let runtime := if baseline then parent/"prefix/libexec/eggshell" else root/"prefix/libexec/eggshell"
  let installation := if baseline then parent/"prefix" else root/"prefix"
  if !baseline then
    discard <| finished "parent-facts-build2"
    let auditor := (project/"tools/research/StudyBuildClosureAudit.lean").toString
    if !(← (records/"native.json").pathExists) then
      discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditor,
        "inspect",build.toString,(records/"native.json").toString]
    check ((← read (records/"native.json")).getObjValD "consistent" == toJson true) "native inputs inconsistent"
    let compared ← IO.Process.output {
      cmd := (compiler/"bin/lean").toString
      args := #["-j1","-M768","--run",auditor,"compare-sources",(parent/"build").toString,
        build.toString,(records/"runtime-sources.json").toString,"Eggshell.Handoff"]
      cwd := some project }
    let common ← read (records/"runtime-sources.json")
    let removed ← IO.ofExcept (common.getObjValAs? (Array String) "removed")
    check (compared.exitCode ≤ 1 &&
      common.getObjValD "directSourceChanges" == toJson #["Eggshell.Handoff"] &&
      common.getObjValD "literalChangesExactlyMatchDeclaredSourceBytes" == toJson true &&
      common.getObjValD "added" == toJson (#[] : Array String) &&
      removed.all (fun name => name.startsWith "tools.research." || name.startsWith "tests."))
      "native source or literal changed beyond Handoff and unused research CLI removal"
    write (records/"source-decision.json") (Json.mkObj [("nativeCorePresent",toJson true),
      ("onlyDirectProductSourceChange",toJson "Eggshell.Handoff"),
      ("embeddedLiteralsMatchDeclaredHandoffBytes",toJson true),
      ("removedResearchOnly",toJson removed),
      ("minimalEntryRetainsSameMemoryCapacityHarness",toJson true),
      ("candidateRuntimeSha256",common.getObjValD "candidateRuntimeSha256")])
    let actual ← read (build/"Eggshell_Handoff.source")
    let (text,_) : String × Array (String × String) ← IO.ofExcept (fromJson? actual)
    let expectedObject := (toJson (build/"Eggshell_Handoff.o").toString).compress
    check (text == (← IO.FS.readFile (source/"Eggshell/Handoff.lean")) &&
      ((← IO.FS.readFile (build/"runtime.rsp")).splitOn "\n").contains expectedObject)
      "the actual linked Handoff is not the source checked by Lean"
    check ((← read (records/"proof-result.json")).getObjValD "candidateHandoffSourceSha256" ==
      toJson (← hash (source/"Eggshell/Handoff.lean"))) "candidate source changed after proof"
    let proof ← IO.FS.readFile (build/"Eggshell_Handoff-lean.stdout")
    check (!proof.contains "sorryAx" && !proof.contains "error:" && !proof.contains "warning:") "native proof failed"
    IO.FS.writeFile (records/"native-proof.txt") proof
    IO.FS.createDirAll (installation/"libexec")
    discard <| command "/bin/ln" #["-s",(build/"StudyMain").toString,runtime.toString]
    discard <| command "/bin/ln" #["-s",(parent/"prefix/share").toString,(installation/"share").toString]
  check (!(← area.pathExists)) "preserve native hook results"
  IO.FS.createDirAll area
  let output := area/"run"
  let config := output/"config.toml"
  let input ← read (parent/"preflight-input.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let environment := environment.map fun (key,value) => (key,
    if key == "EGGSHELL_PREFIX" then some installation.toString
    else if key == "PLUGIN_ROOT" then some (installation/"share/eggshell/codex-plugin").toString
    else if key == "EGGSHELL_CONFIG" then some config.toString
    else if key == "EGGSHELL_HANDOFF_TRACE" then some (area/"discovery.log").toString else value)
  let input := input.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "runtime" (toJson runtime.toString)
    |>.setObjVal! "runtimeSha256" (toJson (← hash runtime))
    |>.setObjVal! "plugin" (toJson (installation/"share/eggshell/codex-plugin").toString)
    |>.setObjVal! "environment" (toJson environment)
    |>.setObjVal! "counts" (toJson (if baseline then #[(4 : Nat)] else #[4,16]))
    |>.setObjVal! "diagnostic" (toJson baseline)
  write (area/"input.json") input
  let unsets := environment.foldl (fun args (key,value) => if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
  guard (if baseline then "current-cleanup-verification" else "parent-facts-hooks")
    (#["/usr/bin/env"]++unsets++assignments++#[runtime.toString,
      if baseline then "owned-selection-capacity" else "parent-facts-capacity",(area/"input.json").toString])

def repairEntry : IO Unit := do
  idle
  let failed ← read (base/"parent-facts-build.guard.json")
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "exitCode" == toJson (1 : Nat) &&
    failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "failed build has not drained"
  write (records/"build-first-rejected.json") (Json.mkObj [("guard",failed),
    ("reason",toJson (← IO.FS.readFile (base/"parent-facts-build.stderr"))),
    ("candidateHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  IO.FS.writeFile (source/"tools/research/ParentFactsRuntime.lean")
    (← IO.FS.readFile (project/"tools/research/ParentFactsRuntime.lean"))
  guard "parent-facts-build2" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"parent-facts-build-settings.json").toString]

def collectRun (baseline : Bool) : IO Unit := do
  idle
  let monitor ← finished (if baseline then "current-cleanup-verification" else "parent-facts-hooks")
  let area := root/(if baseline then "baseline-cleanup" else "hooks")
  let input ← read (area/"input.json")
  let output := area/"run"
  let report ← read (output/"report.json")
  let primes ← IO.ofExcept ((← read (output/"prime.json")).getArr?)
  let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  let mut all := #[]
  for (rows,label) in [(primes,"prime")] ++ phases.toList.map (fun phase =>
      ((phase.getObjValAs? (Array Json) "rows").toOption.getD #[],
        "phase-"++toString ((phase.getObjValAs? Nat "clients").toOption.getD 0))) do
    for row in rows do
      check (row.getObjValD "success" == toJson true) "hook did not pass"
      let client ← IO.ofExcept (row.getObjValAs? Nat "client")
      let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
      let id ← IO.ofExcept (row.getObjValAs? String "receipt")
      let stdout := output/label/s!"client-{client}"/"stdout"
      let raw ← IO.FS.readFile stdout
      let directory := parent/"data/receipts"/id
      let publication := (← read (directory/"published.json")).getObjValD "data"
      check (publication.getObjValD "output" == toJson raw &&
        publication.getObjValD "sha256" == toJson (← hash stdout) &&
        publication.getObjValD "replyComplete" == toJson true) "actual stdout/publication mismatch"
      let parsed ← IO.ofExcept (Json.parse raw)
      let body ← IO.ofExcept ((parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      check (body == (← IO.FS.readFile (base/"snapshot-scheduling/diagnostic"/s!"topic-{topic}"/"body.txt")))
        "original body changed"
      let search := (← read (directory/"search.json")).getObjValD "data"
      let trace := search.getObjValD "trace"
      check (trace.getObjValD "route" == toJson "configured" &&
        trace.getObjValD "semantic" == toJson "completed") "semantic route failed"
      let synapse := (← read (directory/"synaptic-delivery.json")).getObjValD "data"
      check (synapse.getObjValD "complete" == toJson true &&
        synapse.getObjValD "packetVerified" == toJson true) "synaptic packet failed"
      let ack := (← read (directory/"ack.json")).getObjValD "data"
      check (ack.getObjValD "offerAccepted" == toJson true &&
        ack.getObjValD "rpcCompleted" == toJson true) "ACK failed"
      all := all.push (row.setObjVal! "phase" (toJson label)
        |>.setObjVal! "stdoutSha256" (publication.getObjValD "sha256")
        |>.setObjVal! "search" search)
  let originalFiles : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  let db ← IO.ofExcept (input.getObjValAs? String "project")
  for (relative,expected) in originalFiles do
    check ((← hash (.mk db/relative)) == expected) "original DB changed"
  let publisher ← read (output/"publisher-shutdown.json")
  let frontend ← read (output/"frontend-shutdown.json")
  for stopped in [publisher,frontend] do
    check (stopped.getObjValD "processExited" == toJson true &&
      stopped.getObjValD "daemonExitCode" == toJson (0 : Nat)) "service did not stop normally"
  let expected := if baseline then 7 else 23
  check (all.size == expected) "native clients are missing"
  let enoughForComparison := !baseline && (phases[1]?.bind (fun phase =>
    (phase.getObjValAs? Nat "wallMs").toOption)).any (· < 11000)
  let destination := if baseline then project/"docs/cleanup/current-artifacts/verification.json" else records/"hooks.json"
  write destination (Json.mkObj [("guard",monitor),("report",report),("rows",toJson all),
    ("allActualBodiesAndAcksEqual",toJson true),("originalSourceFiles",toJson originalFiles),
    ("publisherShutdown",publisher),("frontendShutdown",frontend),
    ("predeclared16SecondGateMet",toJson enoughForComparison),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  IO.println s!"Verified {all.size} actual bodies and ACKs. Next comparison gate: {enoughForComparison}."

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["prune-changed-clones"] => pruneChangedClones
  | ["prepare-proof"] => prepareProof
  | ["repair-proof"] => repairProof
  | ["finish-proof"] => finishProof
  | ["collect-proof"] => collectProof
  | ["resume-cache"] => resumeCache
  | ["prepare-baseline"] => prepareRun true
  | ["prepare-hooks"] => prepareRun false
  | ["repair-entry"] => repairEntry
  | ["collect-baseline"] => collectRun true
  | ["collect-hooks"] => collectRun false
  | _ => throw (IO.userError "prepare required")
end ParentFactsStudy
def main := ParentFactsStudy.main
