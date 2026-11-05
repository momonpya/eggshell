import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def dist (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("sum",toJson (values.foldl (·+·) 0)),
    ("min",toJson sorted[0]?),("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def number (value : Json) (key : String) := (value.getObjValAs? Nat key).toOption.getD 0
def summary (report : Json) : Json := Id.run do
  let phases := #[report.getObjValD "prime",report.getObjValD "first",report.getObjValD "second"]
  let rows := phases.flatMap (arr · "rows")
  let waves := phases.map fun phase =>
    let receipts := arr phase "receipts"
    Json.mkObj [("name",phase.getObjValD "name"),("wallMs",phase.getObjValD "wallMs"),
      ("cpuIntervalMs",phase.getObjValD "cpuIntervalMs"),("persistentCpu",phase.getObjValD "persistentCpu"),
      ("lostPids",phase.getObjValD "lostPids"),
      ("latency",dist ((arr phase "rows").map (number · "elapsedMs"))),
      ("queue",dist (receipts.map (fun receipt => number (receipt.getObjValD "operation-service") "queueMs"))),
      ("work",dist (receipts.map (fun receipt => number (receipt.getObjValD "operation-service") "workMs"))),
      ("semanticStatus",toJson (receipts.map fun receipt =>
        (receipt.getObjValD "search-phase-semantic").getObjValD "status"))]
  return Json.mkObj [("runtimeSha256",report.getObjValD "runtimeSha256"),("waves",toJson waves),
    ("rows",toJson rows),("bothFields",toJson (rows.filter (fun row => row.getObjValD "bothFields" == toJson true)).size),
    ("allAcked",toJson (rows.all (fun row => row.getObjValD "acknowledged" == toJson true))),
    ("headsUnchanged",report.getObjValD "originalHeadsUnchanged")]
def body (root : System.FilePath) (session : String) : IO String := do
  let value ← read (root/(session++".stdout"))
  return ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
structure Offer where
  closure : List Nat
  covers : List Nat
  deriving FromJson
def parts (directory : System.FilePath) (plan : Json) (area field : String) : IO (Array Json) := do
  let some descriptor := (arr plan "diagnosticParts").find? (fun row =>
      row.getObjValD "area" == toJson area && row.getObjValD "field" == toJson field) |
    throw (IO.userError "missing diagnostic descriptor")
  let mut rows := #[]
  for index in [:number descriptor "parts"] do
    let record ← read (directory/s!"selection-{area}-{field}-{index}.json")
    unless record.getObjValD "receipt" == toJson directory.fileName.get! &&
        record.getObjValD "stage" == toJson s!"selection-{area}-{field}-{index}" do
      throw (IO.userError "diagnostic part identity changed")
    rows := rows++(← IO.ofExcept ((record.getObjValD "data").getArr?))
  unless rows.size == number descriptor "rows" do throw (IO.userError "diagnostic part count changed")
  return rows
def selectionEvidence : IO Unit := do
  let root := base/"maintenance-scope-selection1-result"
  let mut records := #[]
  for entry in ← (root/"private/receipts").readDir do
    unless ← (entry.path/"request.json").pathExists do continue
    let request := (← read (entry.path/"request.json")).getObjValD "data"
    unless request.getObjValD "session" == toJson "selection-0" do continue
    let plan := (← read (entry.path/"selection-plan.json")).getObjValD "data"
    let costs : Array (Nat × Nat) ← IO.ofExcept (fromJson? (.arr (← parts entry.path plan "selectorInput" "costs")))
    let weights : Array Nat ← IO.ofExcept (fromJson? (.arr (← parts entry.path plan "selectorInput" "weights")))
    let offers : Array Offer ← IO.ofExcept (fromJson? (.arr (← parts entry.path plan "selectorInput" "offers")))
    let fixed : Nat × Nat ← IO.ofExcept (fromJson? (.arr (← parts entry.path plan "selectorInput" "fixed")))
    let limit : Nat × Nat ← IO.ofExcept (fromJson? (.arr (← parts entry.path plan "selectorInput" "limit")))
    let selected : Array Nat ← IO.ofExcept (fromJson? (.arr (← parts entry.path plan "selectionWitness" "compiledSelected")))
    let units ← parts entry.path plan "selectionWitness" "units"
    let some family := (arr plan "rangeAudit").find? (fun row =>
      row.getObjValD "owner" == toJson "v11478008332843232939") | throw (IO.userError "target family missing")
    let familyId := number family "id"
    let mut nodes : Array Nat := #[]
    let mut covered : Array Nat := #[]
    for index in selected do
      let some offer := offers[index]? | throw (IO.userError "selected offer missing")
      for node in offer.closure do unless nodes.contains node do nodes := nodes.push node
      for cue in offer.covers do unless covered.contains cue do covered := covered.push cue
    let mut used := fixed
    for node in nodes do
      let some charge := costs[node]? | throw (IO.userError "charged node missing")
      used := (used.1+charge.1,used.2+charge.2)
    let mut targets := #[]
    for index in [:units.size] do
      let unit ← IO.ofExcept (units[index]!.getArr?)
      unless unit[0]? == some (toJson familyId) do continue
      let some offer := offers[index]? | throw (IO.userError "target offer missing")
      let mut after := used
      for node in offer.closure.eraseDups do
        unless nodes.contains node do
          let some charge := costs[node]? | throw (IO.userError "target charged node missing")
          after := (after.1+charge.1,after.2+charge.2)
      let mut gain := 0
      let mut uncovered := 0
      for cue in offer.covers.eraseDups do
        unless covered.contains cue do
          let some weight := weights[cue]? | throw (IO.userError "target cue missing")
          gain := gain+weight
          uncovered := uncovered+1
      targets := targets.push (Json.mkObj [("unit",toJson index),("range",unit[1]!),
        ("afterCost",toJson after),("fitsAfterSelected",toJson (after.1 ≤ limit.1 && after.2 ≤ limit.2)),
        ("uncoveredCues",toJson uncovered),("marginalGain",toJson gain)])
    let domain := (← read (entry.path/"delivery-domain.json")).getObjValD "data"
    records := records.push (Json.mkObj [("case",toJson (0 : Nat)),("family",family),
      ("selectedCost",toJson used),("limit",toJson limit),("targetOffers",toJson targets),
      ("domain",domain),("receipt",toJson entry.fileName)])
  IO.FS.writeFile (workspace/"docs/candidates/worker-cpu/selection-evidence.json") (Json.mkObj [
    ("traces",toJson records),("actualBodies",← read (root/"report.json"))]).pretty
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal retained artifact")
  return (result.stdout.splitOn " ").headD ""
def captureRecords : IO Unit := do
  let folder := workspace/"docs/candidates/maintenance-scope"
  let mut guards := #[]
  let mut logs := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "worker-cpu-" || entry.fileName.startsWith "maintenance-scope-" do continue
    if entry.fileName.endsWith ".guard.json" then
      let record ← read entry.path
      unless record.getObjValD "state" == toJson "finished" && arr record "ownedPids" == #[] do
        throw (IO.userError "do not seal a live guard")
      guards := guards.push (entry.fileName,record)
    if entry.fileName.endsWith ".log" then
      let text ← IO.FS.readFile entry.path
      logs := logs.push (Json.mkObj [("name",toJson entry.fileName),("sha256",toJson (← hash entry.path)),
        ("lineCount",toJson (text.splitOn "\n" |>.filter (!·.isEmpty) |>.length)),
        ("failureExcerpt",toJson (if text.contains "error" || text.contains "failed" then
          (text.drop (text.length-1800)).toString else ""))])
  IO.FS.writeFile (folder/"guards.json") (toJson guards).pretty
  IO.FS.writeFile (folder/"attempts.json") (toJson logs).pretty
  IO.FS.writeFile (folder/"checks.json") (← IO.FS.readFile (base/"maintenance-scope-checks1-result/report.json"))
  IO.FS.writeFile (folder/"laws.txt") (← IO.FS.readFile (base/"maintenance-scope-build/tools_research_MaintenanceScopeChecks-lean.stdout"))
  IO.FS.writeFile (folder/"contract-audit.txt") (← IO.FS.readFile (base/"maintenance-scope-build/Eggshell_ContractAudit-lean.stdout"))
  IO.FS.writeFile (workspace/"docs/candidates/worker-cpu/original-ranks.json")
    (← IO.FS.readFile (base/"worker-cpu-native-profile1-result/original-ranks.json"))
  IO.FS.writeFile (workspace/"docs/candidates/worker-cpu/original-audit.json")
    (← IO.FS.readFile (base/"worker-cpu-native-profile1-result/original-audit.json"))
  IO.FS.writeFile (workspace/"docs/candidates/worker-cpu/heads.json")
    (← IO.FS.readFile (base/"worker-cpu-native-profile1-result/heads.json"))
  IO.FS.writeFile (workspace/"docs/candidates/worker-cpu/frozen-required.json")
    (← IO.FS.readFile (base/"worker-cpu-native-profile1-result/frozen-required.json"))
  for (index,name) in [(0,"cpu-wave-a-0"),(28,"cpu-wave-b-28")] do
    let actual ← body (base/"worker-cpu-native-profile1-result") name
    let digest ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some actual)
    unless digest.exitCode == 0 do throw (IO.userError "cannot seal exact body bytes")
    IO.FS.writeFile (workspace/s!"docs/candidates/worker-cpu/actual-case-{index}.json")
      (Json.mkObj [("body",toJson actual),("utf8Bytes",toJson actual.utf8ByteSize),
        ("sha256",toJson ((digest.stdout.splitOn " ").headD ""))]).pretty
  let runtime := base/"maintenance-scope-build/StudyMain"
  let client := base/"worker-cpu-build/StudyMain"
  IO.FS.writeFile (folder/"identity.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (base/"metadata-ingress-candidate-build/StudyMain"))),
    ("candidateRuntimeSha256",toJson (← hash runtime)),("nativeClientSha256",toJson (← hash client)),
    ("candidateHooksSha256",toJson (← hash (base/"interest-traffic-core/Eggshell/PluginHooks.lean"))),
    ("parentHooksSha256",toJson (← hash (base/"maintenance-scope-baseline-core/Eggshell/PluginHooks.lean"))),
    ("productAdopted",toJson false)]).pretty
def main : IO Unit := do
  let output := workspace/"docs/candidates/maintenance-scope/evidence.json"
  let mut pairs := #[]
  for index in [:3] do
    let parent := base/s!"worker-cpu-pair-{index}-parent-result"
    let candidate := base/s!"worker-cpu-pair-{index}-candidate-result"
    let p ← read (parent/"report.json")
    let c ← read (candidate/"report.json")
    unless (← read (parent/"heads.json")) == (← read (candidate/"heads.json")) do
      throw (IO.userError "paired profiles changed original heads")
    let mut checked := 0
    let mut unequal := #[]
    for phase in ["prime","first","second"] do
      let prows := arr (p.getObjValD phase) "rows"
      let crows := arr (c.getObjValD phase) "rows"
      unless prows.size == crows.size do throw (IO.userError "unequal question counts")
      for (pr,cr) in prows.zip crows do
        unless pr.getObjValD "case" == cr.getObjValD "case" do throw (IO.userError "paired questions differ")
        let session ← IO.ofExcept (pr.getObjValAs? String "session")
        unless (← body parent session) == (← body candidate session) do
          unequal := unequal.push (phase,number pr "case")
        checked := checked+1
    pairs := pairs.push (Json.mkObj [("pair",toJson index),("parent",summary p),("candidate",summary c),
      ("actualBodiesChecked",toJson checked),("unequalBodies",toJson unequal)])
  let initial ← read (base/"worker-cpu-native-profile1-result/report.json")
  let records := Json.mkObj [("plan",← read (workspace/"docs/candidates/maintenance-scope/plan.json")),
    ("initialCpuDiagnostic",summary initial),("pairs",toJson pairs),
    ("productAdopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson "0/18")]
  IO.FS.writeFile output records.pretty
  selectionEvidence
  captureRecords
