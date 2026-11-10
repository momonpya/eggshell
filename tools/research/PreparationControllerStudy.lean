import tools.research.StudyLocal
open Lean StudyLocal

def fixed := base/"current-six/fixed-sequence"
def reports := project/"docs/candidates/stable-source-rows/sequence"
def helper := fixed/"preparation-build"
def historyHelper := fixed/"preparation-history-build"

def replaceOnce (source needle replacement : String) : IO String := do
  check ((source.splitOn needle).length == 2) ("expected one preparation boundary: "++needle)
  return source.replace needle replacement

def main (args : List String) : IO Unit := do
  if args == ["prepare-history"] then
    idle
    let source := fixed/"preparation-history-source"
    materialize helper source historyHelper "tools.research.StudyMain" "fixed-sequence-preparation-history-settings.json"
    for name in #["StudyReadiness","StudyHistory"] do
      let relative := "tools/research/"++name++".lean"
      IO.FS.writeFile (source/relative) (← IO.FS.readFile (project/relative))
    copyLocalArtifacts helper historyHelper
    guard "fixed-sequence-preparation-history-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,
      (base/"fixed-sequence-preparation-history-settings.json").toString]
  else if args == ["prepare"] then
    idle
    let source := fixed/"preparation-source"
    materialize (fixed/"controller-build") source helper "tools.research.StudyMain"
      "fixed-sequence-preparation-settings.json"
    for name in #["StudyReadiness","StudyStages","StudyStageClose"] do
      let relative := "tools/research/"++name++".lean"
      IO.FS.writeFile (source/relative) (← IO.FS.readFile (project/relative))
    let entry := source/"tools/research/StudyMain.lean"
    let text ← replaceOnce (← IO.FS.readFile entry)
      "StudyStages.run input digest" "StudyStages.run input digest (some (← IO.appPath).toString)"
    let text ← replaceOnce text "StudyStageClose.run stage digest output"
      "StudyStageClose.run stage digest output (some (← IO.appPath).toString)"
    IO.FS.writeFile entry text
    copyLocalArtifacts (fixed/"controller-build") helper
    guard "fixed-sequence-preparation-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,
      (base/"fixed-sequence-preparation-settings.json").toString]
  else if args == ["audit"] || args == ["audit-history"] then
    let tag := if args == ["audit-history"] then "fixed-sequence-preparation-history" else "fixed-sequence-preparation"
    discard <| finished (tag++"-build")
    guard (tag++"-audit") #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/PreparationControllerStudy.lean").toString,
      if args == ["audit-history"] then "audit-history-worker" else "audit-worker"]
  else if args == ["audit-worker"] || args == ["audit-history-worker"] then
    let selected := if args == ["audit-history-worker"] then historyHelper else helper
    let reportStem := if args == ["audit-history-worker"] then "preparation-history" else "preparation"
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",selected.toString,(reports/(reportStem++"-native.json")).toString]
    discard <| audit #["common-sources",(base/"current-six/stable-source-rows/build").toString,
      selected.toString,(reports/(reportStem++"-sources.json")).toString]
  else if args == ["select"] || args == ["select-history"] then
    let reportStem := if args == ["select-history"] then "preparation-history" else "preparation"
    let selected := if args == ["select-history"] then historyHelper else helper
    discard <| finished ("fixed-sequence-"++reportStem++"-audit")
    let sourceAudit ← read (reports/(reportStem++"-sources.json"))
    let digest ← hash (selected/"StudyMain")
    check (sourceAudit.getObjValD "allProductCorePresent" == toJson true &&
      sourceAudit.getObjValD "commonSourcesUnchanged" == toJson true &&
      sourceAudit.getObjValD "auditorSha256" == toJson digest &&
      sourceAudit.getObjValD "productSha256" == toJson (← hash (base/"current-six/stable-source-rows/build/StudyMain")))
      "preparation helper changed product core or lacks its native audit"
    let target := fixed/"cohort/preparation-runner.json"
    if args == ["select"] then check (!(← target.pathExists)) "keep the selected preparation helper"
    let selection := Json.mkObj [
      ("path",toJson (selected/"StudyMain").toString),("sha256",toJson digest),
      ("sourceAudit",toJson (reports/(reportStem++"-sources.json")).toString),
      ("sourceAuditSha256",toJson (← hash (reports/(reportStem++"-sources.json")))),
      ("answeringRunnerUnchanged",toJson true),("productRuntimeUnchanged",toJson true),
      ("modelRetries",toJson (0 : Nat)),("adopted",toJson false)]
    write target selection
    write (reports/(reportStem++"-runner.json")) selection
  else throw (IO.userError "prepare|audit|audit-worker|select")
