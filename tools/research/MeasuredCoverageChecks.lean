import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
open MeasuredCoverage

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def value (p : MeasuredCoverage.Problem) (selected : List Nat) : Nat :=
  (hashDistinct (selected.flatMap fun index => p.cues[index]!.toList)).foldl
    (fun sum cue => sum+p.weights[cue]!) 0

/-- Independent small reference: actual full rendering for every proposal.
This deliberately slow path is confined to tiny differential fixtures. -/
private def reference (p : MeasuredCoverage.Problem) (cost : List Nat → Cost) : List Nat := Id.run do
  let mut selected := []
  for _ in [:p.cues.size] do
    let mut best := none
    for index in [:p.cues.size] do
      if selected.contains index then continue
      let after := selected ++ [index]
      let gain := value p after-value p selected
      if gain == 0 || !fits p.limit (cost after) then continue
      let charged := charge p.limit (cost selected) (cost after)
      if best.all (fun old => better gain charged old.2.1 old.2.2) then
        best := some (index,gain,charged)
    let some (index,_,_) := best | break
    selected := selected ++ [index]
  let mut single := []
  for index in [:p.cues.size] do
    if fits p.limit (cost [index]) && value p single < value p [index] then single := [index]
  return if value p selected < value p single then single else selected

private def rawUnit (family : Nat) (source : String) (first limit : Nat)
    (compact decoded : Bool := false) : UnitPlan := Id.run do
  let raw := String.ofList (source.toList.drop first |>.take (limit-first))
  let context : ContextDelivery := {
    owner := toString family,outcome := "raw",sourceChars := source.length
    fragments := [{first,original := raw,decoded}]
    cues := [(first,limit)],leading := "RAW\n",trailing := "\nEND RAW\n"
    compactCaptions := compact}
  return {
    family
    slice := {owner := none,keys := context.keys,text := context.render,members := [],visibleKeys := [],context := some context}
    ranges := [(first,limit)]}

private def sharedUnit (family : Nat) (rows : Array Synapses.CanonicalSource.StoredRow) : IO UnitPlan := do
  let some part := Synapses.CanonicalSource.Delivery.Part.check? rows |
    throw (IO.userError "nonempty shared fixture required")
  return {family,slice := {owner := none,keys := part.keys,text := "",members := [],visibleKeys := [],shared := some part},ranges := []}

private def originalRow (line : Nat) (owner code : String) : Synapses.CanonicalSource.StoredRow := {
  key := {file := {relative := "opaque.txt",fingerprint := String.ofList (List.replicate 64 'a'),bytes := 100},line}
  code
  origins := #[{
    occurrence := {session := owner,turn := "t",useId := "call"}
    binding := {database := "db",owner,work := "w",first := 0,limit := code.length}}]}

private def mark (slice : TransportSlice) : Nat := if slice.shared.isSome then 1 else 2
private def overhead (mask : Nat) : Cost := if mask == 3 then (24,24) else (30,30)
private def cost (slices : List TransportSlice) : Cost :=
  let mask := slices.foldl (fun mask slice => mask ||| mark slice) 0
  let data := slices.foldl (fun sum slice =>
    (sum.1+slice.text.length,sum.2+slice.text.utf8ByteSize)) (0,0)
  (data.1+(slices.length-1)+(overhead mask).1,data.2+(slices.length-1)+(overhead mask).2)

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new output JSON path required")
  let mut rawChecks := 0
  for source in ["abc日本語xyz12", "first\\nsecond\\\"third"] do
    for compact in [false,true] do
      for decoded in [false,true] do
        let left := rawUnit 0 source 0 8 compact decoded
        for first in [:10] do
          let right := rawUnit 0 source first (min source.length (first+6)) compact decoded
          let firstMeasured := WireMeasure.rawNext none left.slice
          let measured := firstMeasured.bind fun (prior,_,_) => WireMeasure.rawNext (some prior) right.slice
          let actual := join left.slice right.slice
          check (measured.isSome == actual.isSome) "raw renderability differs from original join"
          if let some (measured,_,_) := measured then
            check (some measured.cost == actual.map (fun slice => (slice.text.length,slice.text.utf8ByteSize)))
              "raw overlap/UTF8/JSON length differs from original join"
          rawChecks := rawChecks+1
  let rowA := originalRow 1 "a" "same日本語"
  let rowB := originalRow 2 "a" "other"
  let rowC := originalRow 1 "b" "same日本語"
  let rowD := originalRow 3 "b" "last"
  let mut cases := 0
  for compact in [false,true] do
    let source := "first日本語 second last"
    let sharedA ← sharedUnit 1 #[rowA,rowB]
    let sharedB ← sharedUnit 2 #[rowC,rowD]
    let units := #[rawUnit 0 source 0 10 compact,rawUnit 0 source 7 source.length compact,
      sharedA,sharedB]
    let parts := #[[0],[1],[2],[3],[0,1],[0,2],[1,3],[2,3]]
    let cues := #[#[0],#[1],#[2],#[3],#[0,1,4],#[0,2,5],#[1,3,6],#[2,3,7]]
    let weights := #[10,11,15,17,8,9,10,13]
    let offers : Array (SharedCoverage.Offer 0 weights.size) := cues.map fun row => {
      closure := [],covers := row.toList.filterMap fun cue =>
        if h : cue < weights.size then some ⟨cue,h⟩ else none}
    for budget in [29,30,40,60,80,100,150,200,300,400,500,600,800,1000,1400,2000] do
      let ceiling := (budget,budget+30)
      let compiled : SharedCoverage.Problem := {costs := #[],weights,offers,limit := ceiling}
      let p : MeasuredCoverage.Problem := {weights,cues,limit := ceiling}
      let renderCost := fun selected =>
        (materialize units (hashDistinct (selected.flatMap fun id => parts[id]!))).map cost
          |>.getD (100000,100000)
      let chosen := WireMeasure.choose {marks := mark,baseMarks := 0,overhead} cost 3 units parts compiled []
      if fits ceiling (renderCost []) then
        let wanted := reference p renderCost
        let some (actual,report) := chosen | throw (IO.userError "meter rejected valid reference case")
        check (actual == hashDistinct (wanted.flatMap fun id => parts[id]!))
          "cached marginal choices differ from independent full-render reference"
        let selected ← IO.ofExcept ((report.getObjValD "measured").getObjValAs? (List Nat) "selected")
        check (selected == wanted) "recipe order or stable tie changed"
      else check chosen.isNone "initial over-budget packet accepted"
      cases := cases+1
  let axioms := "checked_within_budget and existing Plan.within_budget inspect the actual final rendering"
  let directory := System.FilePath.mk output
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "result.json") (Json.mkObj [("rawJoinCases",toJson rawChecks),
    ("fullRendererDifferentialCases",toJson cases),("allPassed",toJson true),
    ("budgetBoundary",toJson axioms),("answeringModelCalls",toJson (0 : Nat))]).pretty
  IO.println s!"PASS {rawChecks} raw joins and {cases} full-render selector cases"
