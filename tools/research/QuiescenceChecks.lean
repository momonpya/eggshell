import Main
import Eggshell.ContractAudit
import tools.research.WorkQuiescence
open Lean Eggshell Eggshell.Research Eggshell.Plugin.Publication.Service
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def controls (root destination : String) : IO UInt32 := do
  let directory : System.FilePath := .mk root
  let path : System.FilePath := .mk destination
  unless !(← path.pathExists) do throw (IO.userError "preserve native work-quiescence controls")
  let mut rejected := 0
  for study in ["retention","selector-cleanup","ingress-ownership"] do
    for mode in ["sham","collect"] do
      let name := (if study == "ingress-ownership" then "service-" else "")++mode++".json"
      let value ← read (directory/study/name)
      for endpoint in ["beforeStats","afterStats"] do
        let stats := value.getObjValD endpoint
        unless !retentionIdle stats && retentionIdle stats == WorkQuiescence.idle stats do
          throw (IO.userError "actual service accepted background preparation as idle")
        rejected := rejected+1
  let evidence ← read (directory/"ingress-ownership/evidence.json")
  let waves ← IO.ofExcept (evidence.getObjValAs? (Array Json) "waves")
  let some first := waves[0]? | throw (IO.userError "missing recorded idle positive control")
  unless retentionIdle (first.getObjValD "serviceStats") && !retentionIdle Json.null && !retentionIdle (Json.mkObj []) do
    throw (IO.userError "idle positive/missing-schema native controls failed")
  let report := Json.mkObj [("activePreparationEndpointsRejected",toJson rejected),
    ("actualServiceUsesProvenPredicate",toJson true),("recordedIdlePositiveAccepted",toJson true),
    ("missingCountersRejected",toJson true),("reranModelOrHook",toJson false),("adopted",toJson false)]
  IO.FS.writeFile path report.compress
  IO.println report.compress
  return 0
def main (args : List String) : IO UInt32 := do
  match args with
  | ["quiescence-check",root,destination] => controls root destination
  | other =>
    if other == ["codex-publication-daemon"] && (← IO.getEnv "EGGSHELL_RESEARCH_RETENTION") == some "1" then
      HeapObservation.initializeObserver
    sourceRouteEngine other
