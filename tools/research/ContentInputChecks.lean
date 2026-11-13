import Eggshell.ContentCapture
import Eggshell.SynapseBuild
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Synapses
namespace ContentInputChecks
def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)
def capture (workspace : System.FilePath) (input : Json) : IO Json := do
  let started ← IO.monoMsNow
  let captured ← ContentCapture.captureInputs workspace input none (started+5000)
  return Json.mkObj [("valid",toJson captured.record.valid),("closed",toJson captured.record.closed),
    ("complete",toJson captured.record.complete),("files",toJson captured.record.files),
    ("probes",toJson captured.probes.length),("elapsedMs",toJson ((← IO.monoMsNow)-started))]
def fixtures (mode directory output : String) : IO Unit := do
  check (mode == "original" || mode == "candidate") "explicit expected capture mode required"
  let root := System.FilePath.mk directory
  check (!(← root.pathExists) && !(← System.FilePath.pathExists output)) "fresh independent capture fixtures required"
  IO.FS.createDirAll (root/"data")
  IO.FS.writeFile (root/"data/a.txt") "alpha original evidence\n"
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s","data",(root/"linked").toString]}
  check (linked.exitCode == 0) "symlink control could not be prepared"
  let cases : Array (String × Array String × Nat × Nat) := #[
    ("regular",#["data/a.txt"],1,1),
    ("directory-before-file",#["data","data/a.txt"],0,1),
    ("file-before-directory",#["data/a.txt","data"],0,1),
    ("absent-before-file",#["absent","data/a.txt"],1,1),
    ("symlink-before-file",#["linked/a.txt","data/a.txt"],0,0),
    ("directory-only",#["data"],0,0)]
  let mut reports := #[]
  for (name,paths,oldCount,newCount) in cases do
    let result ← capture root (Json.mkObj [("paths",toJson paths)])
    let files : Array Json ← IO.ofExcept (result.getObjValAs? _ "files")
    let expected := if mode == "original" then oldCount else newCount
    check (files.size == expected) ("unexpected capture domain: "++name)
    check (result.getObjValD "closed" == toJson false) "advisory path hints acquired execution authority"
    reports := reports.push (result.setObjVal! "name" (toJson name)|>.setObjVal! "expectedFiles" (toJson expected))
  IO.FS.writeFile output (Json.mkObj [("mode",toJson mode),("checks",toJson reports),
    ("allPassed",toJson true),("modelOrProductQueryCalled",toJson false),("adopted",toJson false)]).compress
def actual (database workspace owner output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve actual-command capture diagnosis"
  let source ← DB.PageMap.pin (.mk database)
  let reader ← Persistence.Store.NodeReader.new source
  let mut reports := #[]
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    if doc.owner != owner then continue
    let some invocation := doc.workText | throw (IO.userError "original work text is absent")
    let pieces := invocation.splitOn "\n"
    check (pieces.length == 2) "recorded invocation is not a single tool plus literal JSON input"
    let input ← IO.ofExcept (Json.parse pieces[1]!)
    let result ← capture (.mk workspace) input
    let files : List SourceEvidence.File ← IO.ofExcept (result.getObjValAs? _ "files")
    let agrees := files.all fun file => doc.files.any fun recorded =>
      file.relative == recorded.relative && file.content == some ⟨recorded.bytes,recorded.fingerprint⟩
    check agrees "current input capture differs from the originally recorded file fingerprints"
    reports := reports.push (result.setObjVal! "owner" (toJson owner)
      |>.setObjVal! "recordedFiles" (toJson doc.files)
      |>.setObjVal! "currentInputsAgreeWithRecordedFingerprints" (toJson agrees)
      |>.setObjVal! "input" input)
  check (reports.size == 1) "actual original owner is absent or ambiguous"
  check ((← DB.PageMap.pin source.directory).head == source.head) "diagnostic changed source publication"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("sourceUnchanged",toJson true),
    ("diagnosticProbes",toJson reports),("reacquiredHistoricalEvidence",toJson false),
    ("modelOrProductQueryCalled",toJson false),("adopted",toJson false)]).compress
end ContentInputChecks
def main : List String → IO Unit
  | ["suite",mode,root,database,workspace,owner,records] => do
    ContentInputChecks.fixtures mode root (System.FilePath.mk records/(mode++"-checks.json")).toString
    ContentInputChecks.actual database workspace owner (System.FilePath.mk records/(mode++"-actual.json")).toString
  | ["fixtures",mode,root,output] => ContentInputChecks.fixtures mode root output
  | ["actual",database,workspace,owner,output] => ContentInputChecks.actual database workspace owner output
  | _ => throw (IO.userError "ContentInputChecks fixtures MODE ROOT OUTPUT | actual DB WORKSPACE OWNER OUTPUT")
