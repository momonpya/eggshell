module
public import Eggshell.ContentMetadata
public import Eggshell.SynapseBuild
public import Eggshell.CanonicalSourceDelivery
@[expose] public section
namespace Eggshell.Research.FrozenCanonicalBasis
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource

def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

/-- Read-only restoration of the original rows and sealed source supplement.
No provider, warm, inferred dependency, rewritten DB or new seed. -/
def load (study root : System.FilePath) : IO (DB.PageMap.Snapshot × Array StoredRow) := do
  let source ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let initial ← read (study / "seed-originals.json")
  check (initial.getObjValD "sourceHead" == toJson source.head) "original source changed"
  let rows : Array StoredRow ← IO.ofExcept (initial.getObjValAs? _ "canonicalRows")
  let refinement ← read (root / "anchored-capture/seed-refinement.json")
  check (refinement.getObjValD "source" == toJson source.head) "supplement source changed"
  let extras : Array (Nat × String × ContentCapture.Supplement) ←
    IO.ofExcept (refinement.getObjValAs? _ "supplements")
  let byId := Std.HashMap.ofArray (extras.map fun (id,owner,extra) => (id,(owner,extra)))
  let reader ← Persistence.Store.NodeReader.new source
  let mut additions := #[]
  for entry in ← Build.entries source do
    let some (owner,extra) := byId[entry.id]? | continue
    let doc ← Build.document reader entry.id
    check (owner == doc.owner) "supplement owner changed"
    let some parent ← ContentMetadata.load? source entry.id doc | continue
    unless extra.sealed do continue
    let catalog ← IO.ofExcept (ContentMetadata.catalogSupplement source.head.identity doc parent extra)
    for located in catalog.located do
      let some file := located.read.source.file? | throw (IO.userError "supplement lost original coordinates")
      let origins := doc.occurrences.map fun occurrence => (⟨occurrence,located.read.binding⟩ : Origin)
      additions := additions.push ⟨⟨file,located.read.source.first⟩,located.text,origins⟩
  let result ← IO.ofExcept (Delivery.merge (rows ++ additions))
  check (result.size == 8276) "original payload basis changed"
  return (source,result)
end Eggshell.Research.FrozenCanonicalBasis
