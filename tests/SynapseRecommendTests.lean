import Eggshell.SynapseTransport

open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.Extraction

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def query : String := String.ofList (List.replicate 64 'b')
private def file : File := ⟨"src/source.cpp", String.ofList (List.replicate 64 'c'), 1000⟩
private def occurrence (name : String) : Occurrence := ⟨"test", "turn", name⟩

private def owner (name : String) (line : Nat) : OutcomeEdge := Id.run do
  let work := Value.text ("shell\n" ++ (Json.mkObj [
    ("command", toJson s!"nl -ba src/source.cpp | sed -n '{line},{line}p'")]).compress)
  let output := Value.text s!"  {line}\tSYMBOL_{name}\n"
  let identity := Value.applyList .occurrence [Ref.semantic output, Ref.semantic work,
    Ref.exact (.text "test"), Ref.exact (.text "turn"), Ref.exact (.text name)]
  return OutcomeEdge.make work output [identity] (by simp) (by simp [maxOutcomeObservations])

private def provenance : List SourceEvidence.Record := [{
  workspace := "/fixture", complete := true
  files := [⟨file.relative, some ⟨file.bytes, file.fingerprint⟩⟩]}]

private def nativeOwner (database name : String) (line : Nat) : Transport.Owner :=
  ⟨database, owner name line, provenance⟩

private def row (original : Transport.Owner) : IO Read := do
  let doc ← IO.ofExcept original.document
  let reads ← IO.ofExcept (recordedRows original.database doc)
  let some read := reads[0]? | throw (IO.userError "fixture source has no original row")
  return read

private def usage (name : String) (source : Range) (kind : UsageKind) : Fact :=
  .used ⟨⟨occurrence name, 0⟩, query, source, kind⟩

private def scenario (root : System.FilePath) : IO Unit := do
  let source ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "authority")).compress
  let database := source.head.identity
  let owners := #[nativeOwner database "A" 11, nativeOwner database "B" 21,
    nativeOwner database "C" 31, nativeOwner database "D" 41, nativeOwner database "E" 51]
  let a ← row (nativeOwner database "A" 11)
  let b ← row (nativeOwner database "B" 21)
  let c ← row (nativeOwner database "C" 31)
  let d ← row (nativeOwner database "D" 41)
  let e ← row (nativeOwner database "E" 51)
  let claim : Claim := ⟨database, "answer", 1, 10⟩
  let support ← IO.ofExcept (Support.checked a a.source claim)
  let consumption : Consumption := {
    producer := b.occurrence, consumer := a.occurrence
    producerFinish := 10, consumerStart := 20, kind := .identifier, term := "SYMBOL_B"
    inputFirst := 1, inputLimit := 9, outputFirst := 1, outputLimit := 9, rows := #[b.source] }
  let group := Group.answer database "other-answer"
  let _ ← Index.replace source .database .shared #[.read a, .read b, .read c, .read d, .read e,
    .supports support, .consumed consumption, .coquoted group a.source, .coquoted group c.source]
  let _ ← Index.replace source .user .usage #[usage "missing" d.source .omittedThenRead,
    usage "positive-same" d.source .deliveredThenCited, usage "positive" e.source .deliveredThenCited,
    usage "reread" c.source .reread, usage "changed" c.source .sourceChanged]
  let prepared ← Recommend.prepare source true
  let result ← prepared.collect #[("answer", 7)] query ((← IO.monoMsNow)+3000)
  check (result.complete && result.offers.any (·.kind == "support") &&
    result.offers.any (·.kind == "consumption") && result.offers.any (·.kind == "coquotation") &&
    result.offers.any (·.kind == "omitted_then_read") && result.offers.any (·.kind == "delivered_then_cited"))
    "one of the three recommendation relations was not used"
  check (result.offers.all (fun offer => offer.kind != "reread" && offer.kind != "source_changed") &&
    !(result.offers.any (fun offer => offer.source == d.source && offer.kind == "delivered_then_cited")))
    "ordinary reread or positive exposure overrode checked omission"
  check (result.offers.all (fun offer => match offer.fact with
    | .used _ => true | _ => offer.priority == 7)) "original nomination priority was lost"
  let limited ← prepared.collect #[("answer", 7)] query ((← IO.monoMsNow)+3000) {requests := 0}
  let bytes ← prepared.collect #[("answer", 7)] query ((← IO.monoMsNow)+3000) {bytes := 1}
  check (!limited.complete && limited.admitted.isEmpty && !bytes.complete && bytes.admitted.isEmpty && bytes.bytes == 0)
    "partial or byte-limited traversal changed the packet"
  let plan ← Transport.build #[prepared] #[("answer", 7)] owners query ((← IO.monoMsNow)+3000)
  check (plan.complete && plan.owners.all (fun original => !original.located.isEmpty))
    "recommendations were not projected onto all original owner rows"
  let wrong := {d.source with file := {d.source.file with fingerprint := String.ofList (List.replicate 64 'd')}}
  let some offer := Recommend.Offer.check? wrong 0 (usage "wrong-fingerprint" wrong .omittedThenRead)
      ⟨Index.contentKey (usage "wrong-fingerprint" wrong .omittedThenRead), rfl⟩ |
    throw (IO.userError "invalid alternate fingerprint fixture")
  check ((Recommend.locate #[offer] #[d]).isEmpty) "a changed fingerprint acquired old source coordinates"
  let shared ← Index.prepare source .database .shared
  let some sharedReader ← Index.open? source .database .shared | throw (IO.userError "missing shared index")
  let oldHead := shared.head
  let oldIdentity := prepared.identity
  let _ ← Index.publishDelta source .user .usage none {added := #[usage "later-missing" c.source .omittedThenRead]}
  let fresh ← Recommend.prepare source true
  check (fresh.identity != oldIdentity) "private feedback did not invalidate packet memo input"
  let pinned ← prepared.collect #[("answer", 7)] query ((← IO.monoMsNow)+3000)
  check (!(pinned.offers.any (fun offer => offer.source == c.source && offer.kind == "omitted_then_read")))
    "a fixed request observed a later private index"
  let latest ← fresh.collect #[("answer", 7)] query ((← IO.monoMsNow)+3000)
  check (latest.offers.any (fun offer => offer.source == c.source && offer.kind == "omitted_then_read"))
    "the next request did not observe new feedback"
  check (sharedReader.index.head == oldHead && (← DB.PageMap.pin source.directory).head == source.head)
    "recommendation planning wrote the source graph"
  IO.FS.writeFile (root / "receipt.json") (plan.receipt "").compress
  IO.println s!"Lean recommendation tests passed: offers={result.offers.size} requests={result.requests} bytes={result.bytes}; three relations, omitted feedback, original rows, private index pinning, bounds and no graph mutation"

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "SynapseRecommendTests NEW-DIRECTORY")
  let root := System.FilePath.mk path
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute fixture required")
  IO.FS.createDirAll root
  scenario root
