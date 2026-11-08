import tools.research.SelectorFixture
import tools.research.SupportPresence
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
namespace SupportPresenceChecks
open Research.SupportPresence
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)

@[noinline, nospecialize] def before (keys shared : List String) (probes : List (Nat × String × String × String)) : List Nat :=
  (selectReference keys shared probes (fun (_,whole,prefixKey,owner) => (whole,prefixKey,owner))).map Prod.fst

@[noinline, nospecialize] def after (keys shared : List String) (probes : List (Nat × String × String × String)) : List Nat :=
  (Research.SupportPresence.select keys shared probes (fun (_,whole,prefixKey,owner) => (whole,prefixKey,owner))).map Prod.fst

def controls : IO Nat := do
  let alphabet := ["","a","ab","g:a:z","e:a:z:line","c:hash:1","日本語"]
  let keys := [[]]++alphabet.map (fun a => [a])++alphabet.flatMap (fun a => alphabet.map fun b => [a,b])
  let shared := [[],[""],["a"],["a","a"]]
  let probes := (alphabet.flatMap fun whole => alphabet.flatMap fun prefixKey =>
    alphabet.map fun owner => (whole,prefixKey,owner)).zipIdx.map fun ((whole,prefixKey,owner),index) =>
      (index,whole,prefixKey,owner)
  let mut count := 0
  for values in keys do
    for owners in shared do
      check (before values owners probes == after values owners probes)
        "support membership changed on empty/duplicate/prefix/Unicode inputs"
      count := count+probes.length
  return count

def observe (_choose : Bool) (expected : ServiceChoice) (query : ServiceQuery)
    (_units : Array ServiceUnit) (_pieces : List CuePiece) (source : Synapses.PreparedSourceView.Domain) : IO (Option Json) := do
  let wanted := Std.HashSet.ofArray expected.sourceKeys
  let rows := source.rows.filter (fun row => wanted.contains row.key)
  check (rows.map (·.key) == expected.sourceKeys && !rows.isEmpty) "selected original row order changed"
  let files := Synapses.PreparedFileIdentities.prepare (rows.toList.map (·.key.file))
  let keys := "p:canonical-component" :: rows.toList.map (fun row => Synapses.PreparedFileIdentities.rowKey files row.key)
  let shared := hashDistinct (rows.toList.flatMap fun row => row.origins.toList.map (·.binding.owner))
  check (keys.all (fun key => key.startsWith "c:" || key.startsWith "p:"))
    "this replay measures canonical keys only; do not claim generic/contextual closure capture"
  -- Exact owner IDs and selected original rows, but not a captured finish
  -- closure: g:/e: probes cannot match any canonical c:/p: key. Generic
  -- positive cases are covered separately by the exhaustive controls.
  let probes := query.owners.toList.zipIdx.map fun (owner,index) =>
    (index,"g:"++owner++":canonical-component","e:"++owner++":canonical-component:",owner)
  let expectedSupport := before keys shared probes
  check (expectedSupport == after keys shared probes) "canonical supported owner order changed"
  let input ← IO.mkRef (keys,shared,probes)
  let mut timings := #[]
  for round in [:3] do
    let mut results := #[]
    for proposed in (if round%2 == 0 then [false,true] else [true,false]) do
      let started ← IO.monoNanosNow
      -- The input read is sequenced after the first clock. A pure result
      -- computed earlier for equality cannot be hoisted into this sample.
      let (freshKeys,freshShared,freshProbes) ← input.get
      let result := if proposed then after freshKeys freshShared freshProbes else before freshKeys freshShared freshProbes
      let result ← (← IO.mkRef result).get
      let elapsed := (← IO.monoNanosNow)-started
      check (result == expectedSupport) "timed support owner order changed"
      timings := timings.push (Json.mkObj [("round",toJson round),("proposed",toJson proposed),
        ("nanos",toJson elapsed),("selectedOwners",toJson result.length)])
      results := results.push result
    check (results[0]? == results[1]?) "paired support results differ"
  return some (Json.mkObj [("rows",toJson rows.size),("keys",toJson keys.length),
    ("sharedOwners",toJson shared.length),("ownerProbes",toJson probes.length),
    ("allOrderedSupportIdsEqual",toJson true),("canonicalOnlyNotFullFinishClosure",toJson true),
    ("timings",toJson timings)])
end SupportPresenceChecks
def main (args : List String) : IO Unit := do
  let [project,fixture,output] := args | throw (IO.userError "SupportPresenceChecks PROJECT FIXTURE OUTPUT")
  let cases ← SupportPresenceChecks.controls
  SupportPresenceChecks.check (cases == 78204) "all 78204 boundary predicates required"
  SelectorStructure.runObserved SupportPresenceChecks.observe false (.mk project) (.mk fixture) (.mk output)
