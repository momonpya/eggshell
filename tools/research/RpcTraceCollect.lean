import tools.research.StudyLocal
open Lean StudyLocal
def distribution (values : Array Nat) : Json :=
  let sorted := values.qsort (· < ·)
  Json.mkObj [("count",toJson sorted.size),("minimum",toJson (sorted[0]?.getD 0)),
    ("middleOrderStatistic",toJson (sorted[sorted.size/2]?.getD 0)),
    ("p95OrderStatistic",toJson (sorted[(sorted.size*95/100)]?.getD 0)),("maximum",toJson (sorted.back?.getD 0))]
def events (row : Json) : Array (String × Nat) :=
  (row.getObjValAs? (Array (String × Nat)) "events").toOption.getD #[]
def span (row : Json) (first last : String) : Option Nat := do
  let start ← (events row).find? (·.1 == first)
  let stop ← (events row).find? (·.1 == last)
  some (stop.2-start.2)
def main : IO Unit := do
  idle
  let folder := project/"docs/candidates/rpc-trace"
  let budget ← read (base/"rpc-trace-matched-load-small2.guard.json")
  check (budget.getObjValD "state" == toJson "finished" && budget.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "hook workload still live"
  let metadata := base/"rpc-trace-matched-metadata"
  let mut clients : Std.HashMap String Json := {}
  let mut servers : Std.HashMap String Json := {}
  let mut unconnected := #[]
  for role in ["client","server"] do
    for entry in ← (metadata/role).readDir do
      let value ← read entry.path
      check (value.getObjValD "dropped" == toJson (0 : Nat) && (events value).size ≤ 64 &&
        value.getObjValD "containsRequestOrResponseContent" == toJson false) "invalid bounded metadata"
      match fromJson? (α := String × String) (value.getObjValD "connection") with
      | .error _ => unconnected := unconnected.push value
      | .ok (localAddress,peerAddress) =>
        let key := (toJson (if role == "client" then (localAddress,peerAddress) else (peerAddress,localAddress))).compress
        if role == "client" then
          check (!clients.contains key) "ambiguous client TCP tuple"
          clients := clients.insert key value
        else
          check (!servers.contains key) "ambiguous server TCP tuple"
          servers := servers.insert key value
  let mut spans : Std.HashMap String (Array Nat) := {}
  let mut failures := #[]
  let mut missing := #[]
  let mut longest : Array (Nat × Json) := #[]
  let mut paired := 0
  let mut kinds : Std.HashMap String Nat := {}
  for (key,client) in clients do
    let some server := servers[key]? | missing := missing.push client; continue
    paired := paired+1
    let kind ← IO.ofExcept (client.getObjValAs? String "kind")
    check (server.getObjValD "kind" == toJson kind) "RPC kinds disagree"
    kinds := kinds.insert kind ((kinds[kind]?).getD 0+1)
    let row := Json.mkObj [("client",client),("server",server)]
    if !(events client).any (·.1 == "request:complete") || !(events server).any (·.1 == "send:end") then
      failures := failures.push row
    let elapsed := (span client "connect:start" "request:complete").getD
      ((span client "connect:start" "request:failed").getD 0)
    longest := (longest.push (elapsed,row)).qsort (fun a b => a.1 > b.1) |>.extract 0 12
    for (side,value,first,last) in [("client",client,"connect:start","connect:end"),
        ("client",client,"send:start","send:end"),("client",client,"receive:start","receive:end"),
        ("server",server,"request-read:start","request-read:end"),
        ("server",server,"score-admission:start","score-admission:end"),
        ("server",server,"score-kernel:start","score-kernel:end"),
        ("server",server,"send:start","send:end")] do
      if let some elapsed := span value first last then
        let name := side++":"++first++"/"++last
        spans := spans.insert name (((spans[name]?).getD #[]).push elapsed)
  let unpaired := servers.toArray.filterMap fun (key,row) => if clients.contains key then none else some row
  let unexpected := unpaired.filter fun row => !(["ping","stats","shutdown"].any (fun kind => row.getObjValD "kind" == toJson kind))
  write (folder/"hook-rpc.json") (Json.mkObj [("guard",budget),("pairedConnections",toJson paired),
    ("clientRecords",toJson clients.size),("serverRecords",toJson servers.size),("kinds",toJson kinds.toArray),
    ("failedPairs",toJson failures),("missingServer",toJson missing),("unconnected",toJson unconnected),
    ("unexpectedUnpairedServer",toJson unexpected),("administrativeServerCount",toJson (unpaired.size-unexpected.size)),
    ("spans",Json.mkObj ((spans.toArray.map fun (name,values) => (name,distribution values)).toList)),
    ("longestPairs",toJson longest),("observerMayAffectTimings",toJson true),
    ("stuckFailureReproduced",toJson (!failures.isEmpty || !missing.isEmpty || !unexpected.isEmpty || !unconnected.isEmpty)),
    ("newEightyRuns",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
