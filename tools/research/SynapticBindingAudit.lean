import Eggshell.SynapseTransport
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms ObservationContext.OriginalOwner.Bound.same_native_owner
#print axioms ObservationContext.OriginalOwner.Bound.same_requested_range
#print axioms IndexedBindings.Origin.only_admitted_owner
#print axioms IndexedBindings.Origin.same_database
#print axioms IndexedBindings.Origin.same_source

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def fixtureDoc (raw : String) : Document :=
  ⟨"owner","work",some "not a shell command",some raw,true,
    #[⟨"session-a","turn","call-a"⟩,⟨"session-b","turn","call-b"⟩],#[]⟩

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "preserve existing binding audit")
  IO.FS.createDirAll root
  let raw := (toJson ("header\n" ++ "".intercalate (List.replicate 1200 "日本語 needle suffix\n") ++ "tail\n")).compress
  let doc := fixtureDoc raw
  let some owner := ObservationContext.OriginalOwner.prepare? doc | throw (IO.userError "native original rejected")
  let range := Range.original owner.identity 13 27
  let bound := owner.bind "database" range
  check (bound.size == 2 && bound.all (fun item => item.read.valid &&
    item.read.binding.first == 13 && item.read.binding.limit == 27 && item.read.source == range))
    "arbitrary original interval lost its occurrence or exact binding"
  check ((owner.bind "database" (Range.original {owner.identity with work := "other-work"} 13 27)).isEmpty)
    "another Work could bind the same original bytes"
  check ((owner.bind "database" (Range.original {owner.identity with content := String.ofList (List.replicate 64 '0')} 13 27)).isEmpty)
    "a different original fingerprint could bind"
  check ((owner.bind "database" (Range.original owner.identity 13 (raw.length+1))).isEmpty &&
    (owner.bind "database" (Range.original owner.identity 13 13)).isEmpty)
    "invalid or out-of-body interval was accepted"
  check ((ObservationContext.OriginalOwner.prepare? {doc with native := false}).isNone)
    "an answer became a native observation"
  let file : Synapses.File := ⟨"source/file.cc",String.ofList (List.replicate 64 'a'),200⟩
  let parent : Read := ⟨⟨"session-a","turn","call-a"⟩,⟨.file file,1,10⟩,
    ⟨"database","owner","work",0,200⟩,#[]⟩
  let source : Range := ⟨.file file,4,5⟩
  let support : Support := ⟨parent,source,⟨"database","answer",0,20⟩,
    {parent.binding with first := 30,limit := 45},source⟩
  let allowed := ({} : Std.HashSet String).insert "owner"
  let some origin := IndexedBindings.check? "database" allowed source (.supports support) |
    throw (IO.userError "partial file support rejected")
  check (origin.read.binding.first == 30 && origin.read.binding.limit == 45)
    "file-source lookup inflated the support to the enclosing read"
  let fileDoc := {doc with files := #[file]}
  check (Transport.boundTo "database" fileDoc owner.identity origin.read &&
    !Transport.boundTo "database" doc owner.identity origin.read &&
    !Transport.boundTo "database" {fileDoc with files := #[{file with bytes := 201}]} owner.identity origin.read)
    "file binding bypassed the owner's exact dependency fingerprint"
  check ((IndexedBindings.check? "other-database" allowed source (.supports support)).isNone &&
    (IndexedBindings.check? "database" {} source (.supports support)).isNone)
    "database or admission boundary lost"
  let snapshot ← DB.PageMap.create (root / "source.egg") "source-binding-audit"
  let database := snapshot.head.identity
  let parent := {parent with binding := {parent.binding with database}}
  let support := {support with
    read := parent
    claim := {support.claim with database}
    binding := {support.binding with database}}
  let second := {support with read := {parent with occurrence := ⟨"session-b","turn","call-b"⟩}}
  let exactRead := {origin.read with binding := {origin.read.binding with database}}
  let other := {exactRead with binding := {exactRead.binding with owner := "not-admitted"}}
  let facts := #[Fact.read parent,.supports support,.supports second,.read exactRead,.read other]
  let _ ← Index.replace snapshot .database .shared facts
  let some reader ← Index.open? snapshot .database .shared | throw (IO.userError "missing fixture index")
  let deadline := (← IO.monoMsNow)+10000
  let indexed ← IndexedBindings.lookup reader source allowed deadline
  let reference := facts.filterMap (IndexedBindings.check? database allowed source) |>.map (·.read)
    |>.foldl (fun seen read => seen.insert read) ({} : Std.HashSet Read)
  check (indexed.complete && indexed.origins.size == reference.size &&
    indexed.origins.all (fun item => reference.contains item.read) && reference.size == 2)
    "indexed source binding differs from the complete fact scan"
  let expired ← IndexedBindings.resolve reader #[source] allowed 0
  check (!expired.complete && expired.requests == 0) "expired query was presented as complete"
  let start ← IO.monoMsNow
  let mut checks := 0
  for i in [:4096] do
    let first := i % (raw.length-40)
    let items := owner.bind "database" (Range.original owner.identity first (first+32))
    unless items.size == 2 do throw (IO.userError "direct binding failed in batch")
    checks := checks + items.foldl (fun n item => n+item.read.binding.limit-item.read.binding.first) 0
  IO.FS.writeFile (root / "batch.json") (Json.mkObj [("checks",toJson checks)]).compress
  let elapsed := (← IO.monoMsNow)-start
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("directRanges",toJson (4096 : Nat)),("occurrencesPerRange",toJson (2 : Nat)),
    ("directBindingAndWitnessWriteMs",toJson elapsed),("indexedEqualsFullScan",toJson true),
    ("fileBindingPreservesPartialInterval",toJson true),("invalidOriginRejected",toJson true),
    ("ownerFileFingerprintChecked",toJson true),
    ("deadlineExplicit",toJson true),("warmCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat)),
    ("actualHook",toJson false),("deliveryRecallMeasured",toJson false),("adopted",toJson false)]).pretty
