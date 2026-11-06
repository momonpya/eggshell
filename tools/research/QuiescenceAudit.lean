import tools.research.WorkQuiescence
import Lean.Data.Json.Parser
open Lean Eggshell.Research
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def main (args : List String) : IO Unit := do
  let [root,destination] := args | throw (IO.userError "QuiescenceAudit CANDIDATES REPORT")
  let directory : System.FilePath := .mk root
  let path : System.FilePath := .mk destination
  unless !(← path.pathExists) do throw (IO.userError "preserve work-quiescence audit")
  let mut reports := #[]
  for study in ["retention","selector-cleanup","ingress-ownership"] do
    for mode in ["sham","collect"] do
      let name := (if study == "ingress-ownership" then "service-" else "")++mode++".json"
      let value ← read (directory/study/name)
      let before := value.getObjValD "beforeStats"
      let after := value.getObjValD "afterStats"
      let failed := WorkQuiescence.counters.filter fun key => !WorkQuiescence.zero before key || !WorkQuiescence.zero after key
      reports := reports.push (Json.mkObj [("study",toJson study),("mode",toJson mode),
        ("legacyDeclaredIdle",value.getObjValD "quiescentBeforeAndAfter"),
        ("allRecordedWorkIdle",toJson (WorkQuiescence.idle before && WorkQuiescence.idle after)),
        ("failedCounts",toJson (failed.map fun key => Json.mkObj [("path",toJson key),
          ("before",toJson (WorkQuiescence.count? before key)),("after",toJson (WorkQuiescence.count? after key))]))])
  -- Negative controls include missing data; an empty object is never an idle
  -- service. Positive data comes from the actual recorded schema, not defaults.
  unless !WorkQuiescence.idle Json.null && !WorkQuiescence.idle (Json.mkObj []) do
    throw (IO.userError "missing work counters were accepted as idle")
  let report := Json.mkObj [("observations",toJson reports),("missingCountsRejected",toJson true),
    ("globalContinuousQuiescenceClaim",toJson false),("reranModelOrHook",toJson false)]
  IO.FS.writeFile path report.compress
  IO.println report.compress
