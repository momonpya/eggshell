import Eggshell.Handoff
import Eggshell.CanonicalSourceDelivery

open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.Extraction Eggshell.Synapses.CanonicalSource

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def fingerprint : String := String.ofList (List.replicate 64 'a')
private def file : File := ⟨"src/sample.cpp",fingerprint,200⟩
private def sourceText : String := "     7\t\treturn \"日本語\";\n     8\t}\n"

private def original (session : String) : Transport.Owner := Id.run do
  let work := Value.text ("shell\n" ++ (Json.mkObj [
    ("command",toJson "nl -ba src/sample.cpp | sed -n '7,8p'")]).compress)
  let output := Value.text sourceText
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text session),Ref.exact (.text "turn"),Ref.exact (.text "read")]
  let owner := OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])
  return ⟨"database",owner,[{workspace := "/fixture",complete := true,files := [⟨file.relative,some ⟨file.bytes,file.fingerprint⟩⟩]}]⟩

def main : IO Unit := do
  let a := original "chat-a"
  let b := original "chat-b"
  let first ← IO.ofExcept a.document
  let second ← IO.ofExcept b.document
  let (registry,stats) ← IO.ofExcept (addDocument {} {} "database" first)
  let (registry,_) ← IO.ofExcept (addDocument registry stats "database" second)
  let combined ← IO.ofExcept (Delivery.merge registry.store)
  let shared : Delivery.Part := {rows := combined,plan := "p:fixture"}
  let aRows ← IO.ofExcept (recordedRows "database" first)
  let bRows ← IO.ofExcept (recordedRows "database" second)
  let rows := aRows ++ bRows
  let shown := presented shared.render #[first,second] rows
  check (covered ⟨file,7,8⟩ shown.ranges) "actual shared row bytes were not verified"
  check ((shared.render.splitOn "return").length == 2 && shared.owners.length == 2)
    "payload repeated or original owner witness lost"
  let damaged := presented (shared.render.replace "return" "invented") #[first,second] rows
  check (!covered ⟨file,7,7⟩ damaged.ranges && damaged.uncertain.contains file)
    "damaged literal source was labelled delivered"
  check ((presented (Delivery.locators combined) #[first,second] rows).ranges.isEmpty)
    "position metadata was labelled delivered code"
  check ((presented (shared.render.replace fingerprint (String.ofList (List.replicate 64 'b')))
      #[first,second] rows).ranges.isEmpty) "changed fingerprint reused old code"
  check ((shared.remaining [shared.plan]).isNone) "acknowledged source plan refilled"
  let some firstRow := combined[0]? | throw (IO.userError "missing canonical row")
  let some remaining := shared.remaining [Delivery.rowKey firstRow.key] |
    throw (IO.userError "acknowledging one row removed unrelated evidence")
  check (remaining.rows.size == 1 && !remaining.rows.any (·.key == firstRow.key))
    "acknowledged row resent or another row disappeared"
  let allowed := ({} : Std.HashSet (String × String)).insert ("database",first.owner)
  let indexed := Delivery.byOwner registry allowed
  check (indexed.size == 1 && (indexed[first.owner]?).any (fun rs =>
    rs.all (fun row => row.origins.all (fun origin => origin.binding.owner == first.owner))))
    "unadmitted original owner entered the packet"
  let lookup := Delivery.byOwner registry
    (allowed.insert ("database",second.owner))
  let family := fun (owner : Transport.Owner) => ({
    owner := owner.original
    template := {owner := some owner.original.relation,keys := [],text := "",members := [],visibleKeys := []}
    windows := [0]
    cached := lookup[Plugin.relationKey owner.original.relation]?.getD #[]} : Plugin.SharedRangeAdapter.Family)
  let families := [family a,family b]
  let units := families.zipIdx.flatMap fun (entry,index) => (Plugin.SharedRangeAdapter.prepare index entry).1
  check (!units.isEmpty && units.all (fun unit => unit.slice.members.isEmpty && unit.slice.visibleKeys.isEmpty))
    "shared source prepared a native-control member"
  let pieces := Plugin.SharedRangeAdapter.cuePieces 100000 families units
  let directory := Plugin.SharedRangeAdapter.cueDirectory pieces
  check (directory.2.size == combined.size && pieces.length > directory.2.size)
    "same physical source acquired a separate vote for each owner"
  let some problem := Plugin.SharedRangeAdapter.problem families units pieces (0,0) (10000,40000) |
    throw (IO.userError "shared cost problem did not compile")
  let offers := List.finRange problem.offers.size
  let some head := offers.head? | throw (IO.userError "no original source offer")
  check (SharedCoverage.cost problem offers == SharedCoverage.cost problem [head])
    "duplicate original observation was charged another payload or file header"
  let some materialized := Plugin.SharedRangeAdapter.materialize units.toArray (List.range units.length) |
    throw (IO.userError "shared source materialization failed")
  check (materialized.length == 1 && materialized.all (·.members.isEmpty) &&
    (materialized.head?.bind (·.shared)).any (·.rows.size == combined.size))
    "native rendering duplicated original rows or fabricated control"
  IO.println "Lean actual hook adapter passed: byte-verified rows, metadata exclusion, fingerprints, witnesses, no-refill, shared votes/costs and no control"
