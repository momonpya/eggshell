import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

/- Read-only diagnosis of already recorded hooks. Labels select report rows;
they never enter a product selector, nomination or graph traversal. Unknown
traversal/selection membership must remain unknown, not a zero count. -/
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def read (path : System.FilePath) : IO Json := do
  check ((← path.metadata).byteSize ≤ 64*1024*1024) "unexpected diagnostic input size"
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def array (value : Json) (name : String) : IO (Array Json) :=
  IO.ofExcept (value.getObjValAs? _ name)

private def text (value : Json) (name : String) : IO String :=
  IO.ofExcept (value.getObjValAs? _ name)

private def sha256 (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "could not hash the recorded input"
  let digest := (result.stdout.splitOn " ").headD ""
  check (digest.length == 64) "invalid recorded input digest"
  return digest

private abbrev Occurrence := String × String × String
private def occurrence (value : Json) : IO Occurrence :=
  return (← text value "session",← text value "turn",← text value "useId")

private def rank (owners : Array String) (owner : String) : Option Nat :=
  (owners.toList.zipIdx.find? fun (name,_) => name == owner).map Prod.snd

private def subjectContains (outer inner : Json) : Bool :=
  outer.getObjValD "subject" == inner.getObjValD "subject" &&
    ((outer.getObjValAs? Nat "first").toOption).any (fun a =>
    ((outer.getObjValAs? Nat "last").toOption).any (fun b =>
    ((inner.getObjValAs? Nat "first").toOption).any (fun c =>
    ((inner.getObjValAs? Nat "last").toOption).any (fun d => a ≤ c && d ≤ b))))

def main (args : List String) : IO Unit := do
  let [trialPath,signalsPath,originalsPath,destination] := args |
    throw (IO.userError "recorded readonly comparison, stored signal audit, original row inventory, fresh output")
  let trial := System.FilePath.mk trialPath
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve the previous read-signal diagnosis"
  let result ← read (trial / "result.json")
  let signals ← read signalsPath
  let originals ← read originalsPath
  let source := result.getObjValD "source"
  check (source == signals.getObjValD "source" && source == originals.getObjValD "sourceHead")
    "recorded bodies, graph facts and original rows must share the exact source head"
  check (signals.getObjValD "sourceUnchanged" == toJson true &&
    result.getObjValD "originalSourceUnchanged" == toJson true) "original source checks were not completed"
  let database ← text source "identity"
  let mut owners : Std.HashMap Occurrence (Array (String × String)) := {}
  for row in ← array originals "canonicalRows" do
    for origin in ← array row "origins" do
      let binding := origin.getObjValD "binding"
      check ((← text binding "database") == database) "original inventory crosses a DB identity"
      let key ← occurrence (origin.getObjValD "occurrence")
      let owner := (← text binding "owner",← text binding "work")
      let prior := owners[key]?.getD #[]
      unless prior.contains owner do owners := owners.insert key (prior.push owner)
  let mut requests : Std.HashMap String System.FilePath := {}
  for entry in ← (trial / "receipts").readDir do
    let path := entry.path / "request.json"
    if !(← path.pathExists) then continue
    let request := (← read path).getObjValD "data"
    if request.getObjValD "event" != toJson "UserPromptSubmit" then continue
    let session ← text request "session"
    check (!requests.contains session) "multiple completed prompt receipts for one session"
    requests := requests.insert session entry.path
  let measurements ← array result "results"
  let mut reports := #[]
  let mut digests := #[(trialPath ++ "/result.json",← sha256 (trial / "result.json")),
    (signalsPath,← sha256 signalsPath),(originalsPath,← sha256 originalsPath)]
  for measured in measurements do
    if measured.getObjValD "arm" != toJson "candidate" then continue
    let topic ← IO.ofExcept (measured.getObjValAs? Nat "topic")
    -- This is the completed comparison harness's recorded session naming.
    -- It is not a task/source filter used by the product.
    let session := s!"readonly-candidate-{topic}"
    let some receipt := requests[session]? | throw (IO.userError "candidate prompt receipt missing")
    let body := trial / "candidate" / s!"topic-{topic}/body.txt"
    let bodyDigest ← sha256 body
    check (measured.getObjValD "bodySha256" == toJson bodyDigest) "final actual body changed"
    let domainFile := receipt / "delivery-domain.json"
    let transportFile := receipt / "synaptic-delivery.json"
    let domain := (← read domainFile).getObjValD "data"
    let transport := (← read transportFile).getObjValD "data"
    let nominated : Array String ← IO.ofExcept (domain.getObjValAs? _ "nominated")
    let hydrated : Array String ← IO.ofExcept (domain.getObjValAs? _ "hydrated")
    let focus : Array String ← IO.ofExcept (domain.getObjValAs? _ "focusRanking")
    let selectedRows ← array transport "sharedRows"
    let mut reportRows := #[]
    for unit in ← array signals "rows" do
      if unit.getObjValD "topic" != toJson topic || unit.getObjValD "missing" != toJson true then continue
      let mut origins := #[]
      for saved in ← array unit "reads" do
        let binding := saved.getObjValD "binding"
        let owner ← text binding "owner"
        origins := origins.push (Json.mkObj [
          ("owner",toJson owner),("source",saved.getObjValD "source"),
          ("nominatedRank",toJson (rank nominated owner)),("focusRank",toJson (rank focus owner)),
          ("hydrated",toJson (hydrated.contains owner)),
          ("hasDeliveredSubrange",toJson (selectedRows.any fun shown =>
            subjectContains (saved.getObjValD "source") (shown.getObjValD "source")))])
      let mut consumed := #[]
      for edge in ← array unit "consumed" do
        let key ← occurrence (edge.getObjValD "consumer")
        let consumerOwners := (owners[key]?.getD #[]).map fun (owner,work) => Json.mkObj [
          ("owner",toJson owner),("work",toJson work),
          ("nominatedRank",toJson (rank nominated owner)),("focusRank",toJson (rank focus owner)),
          ("hydrated",toJson (hydrated.contains owner))]
        consumed := consumed.push (Json.mkObj [
          ("term",edge.getObjValD "term"),("kind",edge.getObjValD "kind"),
          ("consumer",edge.getObjValD "consumer"),("consumerOwnersFromInventory",toJson consumerOwners),
          ("unmappedMeansUnknown",toJson true),("routeRootWasEnqueued",Json.null),
          ("admittedHintMembership",Json.null),("selectorCueWeight",Json.null)])
      reportRows := reportRows.push (Json.mkObj [
        ("names",unit.getObjValD "names"),("missing",unit.getObjValD "missing"),
        ("partial",unit.getObjValD "partial"),("origins",toJson origins),
        ("supportCount",unit.getObjValD "supportCount"),("coquotedCount",unit.getObjValD "coquotedCount"),
        ("consumed",toJson consumed),("usage",unit.getObjValD "used")])
    reports := reports.push (Json.mkObj [("topic",toJson topic),("session",toJson session),
      ("receipt",toJson receipt.toString),("actualBodySha256",toJson bodyDigest),
      ("graphInputs",transport.getObjValD "inputs"),("bindingUnresolved",transport.getObjValD "bindingUnresolved"),
      ("requirements",toJson reportRows)])
    for path in #[body,domainFile,transportFile] do digests := digests.push (path.toString,← sha256 path)
  check (reports.size == 3) "all three completed candidate topics must be diagnosed"
  -- Raw hint lists and rejected offer/cue memberships were intentionally not
  -- captured by these ordinary receipts. Never infer their absence from null.
  let report := Json.mkObj [("source",source),("inputSha256",toJson digests),("topics",toJson reports),
    ("limitation",toJson "consumer nomination does not prove root admission, hint transport or selector cue membership"),
    ("requiredDeliveryUnchanged",toJson true),("candidateChanged",toJson false),
    ("newDbOrCacheWrites",toJson (0 : Nat)),("newActualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output report.pretty
  IO.println (Json.mkObj [("topics",toJson reports.size),("newActualHookCalls",toJson (0 : Nat)),
    ("newDbOrCacheWrites",toJson (0 : Nat)),("adopted",toJson false)]).compress
