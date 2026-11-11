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
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U3","--label","a/Eggshell/Handoff.lean",
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
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U3","--label","a/Eggshell/Handoff.lean",
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

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["prune-changed-clones"] => pruneChangedClones
  | ["prepare-proof"] => prepareProof
  | ["repair-proof"] => repairProof
  | ["finish-proof"] => finishProof
  | ["collect-proof"] => collectProof
  | ["resume-cache"] => resumeCache
  | _ => throw (IO.userError "prepare required")
end ParentFactsStudy
def main := ParentFactsStudy.main
