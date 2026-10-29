import Eggshell.CanonicalSourceDelivery
import Eggshell.ContentMetadata
import Eggshell.SynapseBuild
import Lean.Data.Json.Parser
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

private def read (path : String) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (value : Bool) (reason : String) : IO Unit :=
  unless value do throw (IO.userError reason)

/-- Explicit, read-only preparation against every recorded owner. Expected
ranges are opened only after derivation; no question or labels guide alignment. -/
def main (args : List String) : IO Unit := do
  let [database,workspace,originalsPath,inventoryPath,output] := args |
    throw (IO.userError "SOURCE WORKSPACE ORIGINALS INVENTORY NEW-OUTPUT")
  check (!(← System.FilePath.pathExists output)) "preserve previous source refinement"
  let source ← DB.PageMap.pin (.mk database)
  let original ← read originalsPath
  check (original.getObjValD "sourceHead" == toJson source.head) "frozen source head changed"
  let baseline : Array StoredRow ← IO.ofExcept (original.getObjValAs? _ "canonicalRows")
  let baseline ← IO.ofExcept (Delivery.merge baseline)
  let reader ← Persistence.Store.NodeReader.new source
  let mut added : Array StoredRow := #[]
  let mut owners := #[]
  let mut supplements := #[]
  let began ← IO.monoMsNow
  for entry in ← Build.entries source do
    let document ← Build.document reader entry.id
    let some parent ← ContentMetadata.load? source entry.id document | continue
    let some raw := document.source | throw (IO.userError "original content body disappeared")
    let parentDigest := parent.digest
    let started ← IO.monoMsNow
    let supplement ← ContentCapture.refineSaved (.mk workspace) parent raw ((← IO.monoMsNow)+15000)
    check (supplement.boundTo parent raw && parent.digest == parentDigest)
      "parent original or producer changed"
    let elapsed := (← IO.monoMsNow)-started
    if supplement.sealed then
      let catalog ← IO.ofExcept (ContentMetadata.catalogSupplement source.head.identity document parent supplement)
      for located in catalog.located do
        let some file := located.read.source.file? | throw (IO.userError "supplement lost file identity")
        let origins := document.occurrences.map fun occurrence =>
          (⟨occurrence,located.read.binding⟩ : Origin)
        added := added.push ⟨⟨file,located.read.source.first⟩,located.text,origins⟩
    owners := owners.push (Json.mkObj [("owner",toJson document.owner),("parentProducer",toJson parent.implementation),
      ("parentAliases",toJson parent.aliases.size),("addedAliases",toJson supplement.aliases.size),
      ("sealed",toJson supplement.sealed),("failure",toJson supplement.failure),("elapsedMs",toJson elapsed)])
    supplements := supplements.push (entry.id,document.owner,supplement)
  let elapsed := (← IO.monoMsNow)-began
  let merged ← IO.ofExcept (Delivery.merge (baseline ++ added))
  check ((← DB.PageMap.pin (.mk database)).head == source.head) "read-only derivation published to source"
  let targets ← IO.ofExcept ((((← read inventoryPath).getObjValD "source").getObjValD "required").getArr?)
  let mut comparisons := #[]
  for target in targets do
    let path ← IO.ofExcept (target.getObjValAs? String "path")
    let first ← IO.ofExcept (target.getObjValAs? Nat "first")
    let last ← IO.ofExcept (target.getObjValAs? Nat "last")
    let inside := fun row : StoredRow => row.key.file.relative == path && first ≤ row.key.line && row.key.line ≤ last
    let previous := baseline.filter inside
    let current := merged.filter inside
    let keys := Std.HashSet.ofArray (previous.map (·.key))
    let fresh := current.filter fun row => !keys.contains row.key
    comparisons := comparisons.push (Json.mkObj [("target",target),("baselineRows",toJson previous.size),
      ("candidateRows",toJson current.size),("newRows",toJson (fresh.map fun row => (row.key.line,row.code)))])
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("sourceUnchanged",toJson true),
    ("elapsedMs",toJson elapsed),("owners",toJson owners),("baselineRows",toJson baseline.size),
    ("candidateRows",toJson merged.size),("addedProvenanceRows",toJson added.size),
    ("comparisons",toJson comparisons),("supplements",toJson supplements),
    ("labelsUsedForDerivation",toJson false),("actualDeliveryAsserted",toJson false),
    ("newDatabaseOrWarm",toJson false),("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
  IO.println (Json.mkObj [("owners",toJson owners.size),("elapsedMs",toJson elapsed),
    ("baselineRows",toJson baseline.size),("candidateRows",toJson merged.size),
    ("addedProvenanceRows",toJson added.size),("sourceUnchanged",toJson true)]).compress
