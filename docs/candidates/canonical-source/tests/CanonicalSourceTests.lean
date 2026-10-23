import Eggshell.CanonicalSourceCache
import Eggshell.CanonicalSourceLinks
import Eggshell.CanonicalSourcePacket
import Eggshell.SynapseTransport

open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.Extraction Eggshell.Synapses.CanonicalSource

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def fingerprint : String := String.ofList (List.replicate 64 'a')
private def file : File := ⟨"src/sample.cpp",fingerprint,200⟩

private def original (session body : String) (first : Nat := 7) (last : Nat := 8) : Transport.Owner := Id.run do
  let work := Value.text ("shell\n" ++ (Json.mkObj [
    ("command",toJson s!"nl -ba src/sample.cpp | sed -n '{first},{last}p'")]).compress)
  let output := Value.text body
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text session),Ref.exact (.text "turn"),Ref.exact (.text "read")]
  let owner := OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])
  return ⟨"database",owner,[{
    workspace := "/fixture",complete := true
    files := [⟨file.relative,some ⟨file.bytes,file.fingerprint⟩⟩]}]⟩

private def sourceText : String := "     7\t\treturn \"日本語\";\n     8\t}\n"

private def tests : IO Unit := do
  let aOwner := original "first-chat" sourceText
  let bOwner := original "second-chat" sourceText
  let a ← IO.ofExcept aOwner.document
  let b ← IO.ofExcept bOwner.document
  let (first,statistics) ← IO.ofExcept (addDocument {} {} "database" a)
  let (shared,statistics) ← IO.ofExcept (addDocument first statistics "database" b)
  check (shared.atoms.size == 2 && shared.atoms.toArray.all (·.2.origins.size == 2))
    "identical rows from distinct chats did not share one payload with both origins"
  check (statistics.originalRows == 4 && statistics.rejectedRows == 0) "source row census is incomplete"
  let (replay,_) ← IO.ofExcept (addDocument shared statistics "database" b)
  check (replay.store == shared.store) "replaying an observation added another origin or payload"
  let some firstEvent := aOwner.original.observations.head? | throw (IO.userError "missing first occurrence")
  let some secondEvent := bOwner.original.observations.head? | throw (IO.userError "missing second occurrence")
  let combined ← if distinct : firstEvent ≠ secondEvent then
      pure (OutcomeEdge.make aOwner.original.work aOwner.original.outcome [firstEvent,secondEvent]
        (by simp [distinct]) (by simp [maxOutcomeObservations]))
    else throw (IO.userError "different native sessions did not have distinct occurrences")
  let merged : Transport.Owner := {aOwner with original := combined}
  let mergedDocument ← IO.ofExcept merged.document
  let (mergedRows,_) ← IO.ofExcept (addDocument {} {} "database" mergedDocument)
  check (mergedRows.atoms.size == 2 && mergedRows.atoms.toArray.all (·.2.origins.size == 2))
    "an owner with several native occurrences lost a session witness"
  let overlap ← IO.ofExcept (original "overlap-chat" "  8\t}\n  9\tnew-line\n" 8 9).document
  let (overlapping,_) ← IO.ofExcept (addDocument first {} "database" overlap)
  check (overlapping.atoms.size == 3 && (overlapping.atoms[Key.mk file 8]?).any (·.origins.size == 2))
    "overlapping reads with different Work ranges duplicated their common row"
  let conflict ← IO.ofExcept (original "conflict" (sourceText.replace "return" "throw")).document
  check ((addDocument shared statistics "database" conflict).toOption.isNone) "conflicting code silently merged"
  let changed := {b with files := #[{file with fingerprint := String.ofList (List.replicate 64 'b')}]}
  let (separate,_) ← IO.ofExcept (addDocument shared statistics "database" changed)
  check (separate.atoms.size == 4) "changed file fingerprint reused stale rows"
  let raw := (Json.mkObj [("output",toJson sourceText)]).compress
  let (encoded,_) ← IO.ofExcept (addDocument {} {} "database" {a with source := some raw})
  check (encoded.store.map (·.code) == first.store.map (·.code)) "JSON escaping changed Unicode or tabs"
  let restored ← IO.ofExcept (load "database" shared.store)
  check (restored.store == shared.store) "canonical storage roundtrip lost original bindings"
  check ((load "other-database" shared.store).toOption.isNone) "source origin crossed DB authority"
  let some complete := shared.resolve? ⟨file,7,8⟩ | throw (IO.userError "complete range was not resolved")
  check (complete.rows.size == 2 && complete.rows[0]?.any (·.code == "\treturn \"日本語\";"))
    "source payload lost exact indentation or covered rows"
  check ((shared.resolve? ⟨file,7,9⟩).isNone) "partly missing range was presented as complete"
  let aRows ← IO.ofExcept (recordedRows "database" a)
  let bRows ← IO.ofExcept (recordedRows "database" b)
  let some aRow := aRows[0]? | throw (IO.userError "original A row missing")
  let some bRow := bRows[0]? | throw (IO.userError "original B row missing")
  let claim : Claim := ⟨"database","claim",0,10⟩
  let support ← IO.ofExcept (Support.checked aRow aRow.source claim)
  let consumed : Consumption := {
    producer := aRow.occurrence,consumer := bRow.occurrence,producerFinish := 10,consumerStart := 20
    kind := .identifier,term := "return",inputFirst := 1,inputLimit := 7,outputFirst := 1,outputLimit := 7
    rows := #[aRow.source]}
  let usage : Usage := {
    event := ⟨⟨"later-chat","turn","missing-read"⟩,0⟩
    query := String.ofList (List.replicate 64 'b'),source := aRow.source,kind := .omittedThenRead}
  let facts := #[Fact.supports support,.coquoted (.claim claim) bRow.source,.consumed consumed,.used usage]
  let graph := Links.build shared facts
  let sourceKey := Key.mk file 7
  check (graph.unlocated.isEmpty && graph.connected.size == 4 &&
    (graph.witnesses[sourceKey]?).any (·.size == 4))
    "derivation, coquotation and missing-use evidence did not meet at the same original row"
  let replayGraph := Links.build shared (facts++facts)
  check (replayGraph.connected.size == graph.connected.size &&
    (replayGraph.witnesses[sourceKey]?).any (·.size == 4)) "evidence replay inflated the canonical class"
  check ((Links.connect? shared (.coquoted (.claim claim) ⟨file,7,9⟩)).isNone)
    "partly stored dependency was credited as complete"
  let joint : Packet.Input := ⟨"joint",200,#[⟨file,7,8⟩]⟩
  let independent : Packet.Input := ⟨"numerical",100,#[⟨file,7,7⟩]⟩
  let packet ← IO.ofExcept (Packet.prepare shared #[joint,independent,joint] (10000,40000))
  let some output := Packet.fit? packet | throw (IO.userError "canonical packet did not fit")
  check ((Packet.selectedRows packet output.selection).size == 2 &&
    (output.text.splitOn "return").length == 2 &&
    SharedCoverage.benefit packet.problem output.selection.selected == 300)
    "shared payload or cue was rendered or scored more than once"
  check (SharedCoverage.cost packet.problem output.selection.selected ==
    (output.text.length,output.text.utf8ByteSize)) "wire cost differs from the canonical source closure"
  let frame := Packet.fileFrame file shared.store
  let firstText := Packet.rowText {key := ⟨file,7⟩,code := "\treturn \"日本語\";",origins := #[]}
  let oneCost := (Packet.wrapper.length+Packet.footer.length+frame.leading.length+frame.trailing.length+firstText.length,
    Packet.wrapper.utf8ByteSize+Packet.footer.utf8ByteSize+frame.leading.utf8ByteSize+frame.trailing.utf8ByteSize+firstText.utf8ByteSize)
  let tight ← IO.ofExcept (Packet.prepare shared #[joint] oneCost)
  let some insufficient := Packet.fit? tight | throw (IO.userError "empty tight packet failed")
  check ((Packet.selectedRows tight insufficient.selection).isEmpty &&
    SharedCoverage.benefit tight.problem insufficient.selection.selected == 0) "partial dependency was rewarded"
  let mixed ← IO.ofExcept (Packet.prepare shared #[joint,independent] oneCost)
  let some independentOutput := Packet.fit? mixed | throw (IO.userError "independent numerical packet failed")
  check ((Packet.selectedRows mixed independentOutput.selection).size == 1 &&
    SharedCoverage.benefit mixed.problem independentOutput.selection.selected == 100)
    "an incomplete graph dependency suppressed independent numerical evidence"
  let bytes ← IO.ofExcept (Packet.prepare shared #[joint]
    (output.text.length,output.text.utf8ByteSize-1))
  let some byteOutput := Packet.fit? bytes | throw (IO.userError "empty byte-bounded packet failed")
  check ((Packet.selectedRows bytes byteOutput.selection).isEmpty) "UTF-8 byte limit was not enforced"
  IO.println "Lean canonical source passed: cross-chat sharing, replay, conflict, fingerprint, JSON, Unicode, original bindings and complete range"

private structure Requirement where
  name : String
  path : String
  first : Nat
  last : Nat
  originalOwners : Array String
  deriving FromJson

private structure CaseRow where
  stage : Nat
  source : String
  files : Array (String × String)
  required : Array Requirement
  deriving FromJson

private def audit (specification destination : String) : IO Unit := do
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= fromJson? (α := Array CaseRow))
  let mut results := #[]
  for row in cases do
    let path := System.FilePath.mk row.source
    for (name,expected) in row.files do
      check (Sha256.hex (← IO.FS.readBinFile (path/name)) == expected) "frozen source changed"
    let source ← DB.PageMap.pin path
    let started ← IO.monoMsNow
    let prepared ← Cache.refresh source .user
    let some ready ← Cache.open? source .user | throw (IO.userError "fresh canonical cache is not ready")
    let rebuiltMs := (← IO.monoMsNow)-started
    let started ← IO.monoMsNow
    let reused ← Cache.refresh source .user
    let reusedMs := (← IO.monoMsNow)-started
    check (reused.mode == "warm") "new chat would rebuild a warm canonical cache"
    let cache ← Cache.directory source .user
    let payload := cache / (ready.metadata.payload ++ ".json")
    let originalBytes ← IO.FS.readBinFile payload
    FileSystem.atomicExistingBytes payload "broken-canonical-payload".toUTF8
    let rejected ← try let _ ← Cache.open? source .user; pure false catch _ => pure true
    check rejected "corrupted canonical payload was reused"
    let repaired ← Cache.refresh source .user
    check (repaired.mode == "rebuilt" && (← IO.FS.readBinFile payload) == originalBytes)
      "warm did not restore the exact original payload after corruption"
    FileSystem.atomicExistingBytes (cache / "manifest.json") "broken-manifest".toUTF8
    let _ ← Cache.refresh source .user
    check ((← Cache.open? source .user).isSome) "warm could not repair malformed optional metadata"
    let requirements := row.required.map fun requirement =>
      let files := ready.registry.store.filterMap fun atom =>
        if atom.key.file.relative == requirement.path && atom.origins.any
            (fun origin => requirement.originalOwners.contains origin.binding.owner) then some atom.key.file else none
      let stored := files.any fun file => (ready.registry.resolve? ⟨file,requirement.first,requirement.last⟩).isSome
      Json.mkObj [("name",toJson requirement.name),("stored",toJson stored)]
    let result := Json.mkObj [("stage",toJson row.stage),("summary",ready.registry.summary prepared.metadata.statistics),
      ("buildAndReadMs",toJson rebuiltMs),("warmReuseMs",toJson reusedMs),("requirements",toJson requirements)]
    IO.println result.compress
    results := results.push result
    check ((← DB.PageMap.pin path).head == source.head) "canonical cache changed source DB"
    for (name,expected) in row.files do
      check (Sha256.hex (← IO.FS.readBinFile (path/name)) == expected) "canonical preparation mutated frozen source"
  IO.FS.writeFile (.mk destination) (toJson results).compress

def main (arguments : List String) : IO Unit := do
  tests
  if let [specification,destination] := arguments then audit specification destination
  else unless arguments.isEmpty do throw (IO.userError "CanonicalSourceTests [FROZEN-SPEC OUTPUT]")
