import Eggshell.SynapseBundles

open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.Extraction

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def query : String := String.ofList (List.replicate 64 'b')
private def file : File := ⟨"src/source.cpp", String.ofList (List.replicate 64 'c'), 1000⟩
private def occurrence (name : String) : Occurrence := ⟨"bundle", "turn", name⟩

private def original (database name : String) (line : Nat) (fingerprint := file.fingerprint) : Transport.Owner := Id.run do
  let work := Value.text ("shell\n" ++ (Json.mkObj [
    ("command",toJson s!"nl -ba src/source.cpp | sed -n '{line},{line}p'")]).compress)
  let output := Value.text s!"  {line}\tSYMBOL_{name}\n"
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "bundle"),Ref.exact (.text "turn"),Ref.exact (.text name)]
  let owner := OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])
  return ⟨database,owner,[{
    workspace := "/fixture",complete := true
    files := [⟨file.relative,some ⟨file.bytes,fingerprint⟩⟩]}]⟩

private def row (owner : Transport.Owner) : IO Read := do
  let doc ← IO.ofExcept owner.document
  let rows ← IO.ofExcept (recordedRows owner.database doc)
  let some first := rows[0]? | throw (IO.userError "no original fixture row")
  return first

def main (arguments : List String) : IO Unit := do
  let [path] := arguments | throw (IO.userError "SynapseBundleTests NEW-DIRECTORY")
  let root := System.FilePath.mk path
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute fixture required")
  IO.FS.createDirAll root
  let source ← DB.PageMap.create (root / "source.egg") "source-authority"
  let database := source.head.identity
  let aOwner := original database "A" 11
  let bOwner := original database "B" 21
  let cOwner := original database "C" 31
  let dOwner := original database "D" 41
  let owners := #[aOwner,bOwner,cOwner,dOwner]
  let a ← row aOwner
  let b ← row bOwner
  let c ← row cOwner
  let d ← row dOwner
  let claim : Claim := ⟨database,"answer",0,10⟩
  let aSupport ← IO.ofExcept (Support.checked a a.source claim)
  let bSupport ← IO.ofExcept (Support.checked b b.source claim)
  let edge : Consumption := {
    producer := c.occurrence,consumer := b.occurrence,producerFinish := 10,consumerStart := 20
    kind := .identifier,term := "SYMBOL_C",inputFirst := 1,inputLimit := 9,outputFirst := 1,outputLimit := 9
    rows := #[c.source]}
  let positive : Usage := {event := ⟨occurrence "missing",0⟩,query,source := d.source,kind := .omittedThenRead}
  let _ ← Index.replace source .database .shared #[.read a,.read b,.read c,.read d,
    .supports aSupport,.supports bSupport,.coquoted (.claim claim) a.source,.coquoted (.claim claim) b.source,
    .coquoted (.answer database "other") a.source,.coquoted (.answer database "other") c.source,.consumed edge]
  let _ ← Index.replace source .user .usage #[.used positive]
  let prepared ← Recommend.prepare source true
  let plan ← Transport.build #[prepared] #[("answer",7)] owners query ((← IO.monoMsNow)+3000)
  let projected := Bundles.project plan
  check (plan.complete && ["claim","answer","consumption","omitted_then_read"].all fun kind =>
    projected.any (·.demand.kind == kind)) "one of the three graph relations lost its dependency identity"
  let some joint := (Bundles.demands plan).find? (·.kind == "claim") |
    throw (IO.userError "claim was flattened before planning")
  check (joint.sources.size == 2 && projected.any (fun value => value.demand.key == joint.key &&
    value.members.size == 2)) "one claim lost one of its original owners"
  let incomplete := {plan with owners := plan.owners.filter (·.owner.relation != bOwner.original.relation)}
  check (!(Bundles.project incomplete).any (·.demand.key == joint.key))
    "a partly located claim became a complete delivery recipe"
  let changed := #[aOwner,original database "B" 21 (String.ofList (List.replicate 64 'd')),cOwner,dOwner]
  let mismatch ← Transport.build #[prepared] #[("answer",7)] changed query ((← IO.monoMsNow)+3000)
  check (!(Bundles.project mismatch).any (·.demand.key == joint.key)) "a changed fingerprint supplied an old dependency"
  let unknown ← Transport.build #[prepared] #[("answer",7)] owners (String.ofList (List.replicate 64 'e'))
    ((← IO.monoMsNow)+3000)
  check (!(Bundles.project unknown).any (·.demand.kind == "omitted_then_read")) "usage crossed its actual query"
  check ((← DB.PageMap.pin source.directory).head == source.head) "pure bundle planning changed source authority"
  IO.println "Lean synaptic bundles passed: claim across two owners, all three relations, missing member, changed fingerprint, private query and unchanged source graph"
