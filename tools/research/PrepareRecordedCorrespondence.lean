import Eggshell.ContentMetadata
import Eggshell.SynapseBuild
import Eggshell.ProjectSources
import tools.research.RecordedRecoveryContract
import Lean.Data.Json.Parser
open Lean Eggshell Eggshell.Synapses
namespace PrepareRecordedCorrespondence
def check (valid : Bool) (reason : String) : IO Unit :=
  unless valid do throw (IO.userError reason)
def read (path : String) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def derive (database workspace output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve the original correspondence derivation"
  let source ← DB.PageMap.pin (.mk database)
  let reader ← Persistence.Store.NodeReader.new source
  let mut owners := #[]
  let mut additions : Array (Nat × String × ContentCapture.Supplement) := #[]
  let started ← IO.monoMsNow
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    if !doc.native then continue
    let some parent ← ContentMetadata.load? source entry.id doc | continue
    let some raw := doc.source | throw (IO.userError "recorded output is absent")
    let began ← IO.monoMsNow
    let extra ← ContentCapture.recoverSaved (.mk workspace) parent raw (ContentMetadata.originalInputs doc)
      ((← IO.monoMsNow)+15000)
    check (extra.boundTo parent raw) "recovery changed the original capture binding"
    if extra.sealed then
      let _ ← IO.ofExcept (ContentMetadata.catalogSupplement source.head.identity doc parent extra)
      if !extra.aliases.isEmpty then additions := additions.push (entry.id,doc.owner,extra)
    owners := owners.push (Json.mkObj [("owner",toJson doc.owner),("id",toJson entry.id),
      ("parentComplete",toJson parent.complete),("parentAliases",toJson parent.aliases.size),
      ("originalFiles",toJson doc.files.size),("domainFiles",toJson extra.inputs.size),
      ("recoveredAliases",toJson extra.aliases.size),("sealed",toJson extra.sealed),
      ("failure",toJson extra.failure),("elapsedMs",toJson ((← IO.monoMsNow)-began))])
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only recovery changed its original source"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("additions",toJson additions),
    ("owners",toJson owners),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("labelsOrQuestionsUsed",toJson false),("originalSourceUnchanged",toJson true),
    ("newHistoricalCaptureClaimed",toJson false),("actualDeliveryAsserted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
def publish (database derivation output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve prior prepared publication"
  let plan ← read derivation
  let source ← DB.PageMap.pin (.mk database)
  check (plan.getObjValD "source" == toJson source.head &&
    plan.getObjValD "originalSourceUnchanged" == toJson true) "derivation belongs to another fixed source"
  let entries : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept (plan.getObjValAs? _ "additions")
  let reader ← Persistence.Store.NodeReader.new source
  let previous ← Index.open? source .database .shared
  let mut fresh := #[]
  for (id,owner,extra) in entries do
    let doc ← Build.document reader id
    check (doc.owner == owner) "prepared recovery names another original owner"
    let some parent ← ContentMetadata.load? source id doc | throw (IO.userError "original capture header is absent")
    let _ ← IO.ofExcept (ContentMetadata.catalogSupplement source.head.identity doc parent extra)
    let existing ← previous.bindM fun old => ContentMetadata.loadSupplement? old.index source.head.identity id doc parent
    if existing.any (fun old => toJson old == toJson extra) then continue
    fresh := fresh.push (id,extra)
  let result ← Build.refresh source .database fresh
  check ((← DB.PageMap.pin source.directory).head == source.head) "prepared publication changed original authority"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("preparation",toJson result),
    ("derivedOwners",toJson entries.size),("changedOwners",toJson fresh.size),
    ("originalSourceUnchanged",toJson true),("liveFilesOrModelRead",toJson false),
    ("adopted",toJson false)]).compress
def publishProject (directory derivation output : String) : IO Unit := do
  let plan ← read derivation
  let project ← ProjectStore.openProject (.mk directory)
  let mut matching : Array DB.PageMap.Snapshot := #[]
  for owner in [:project.manifest.owners.size] do
    let source ← project.current owner
    if plan.getObjValD "source" == toJson source.head then matching := matching.push source
  check (matching.size == 1) "recovery must name exactly one source of this project"
  let some source := matching[0]? | throw (IO.userError "matched project source disappeared")
  publish source.directory.toString derivation output
end PrepareRecordedCorrespondence
def main : List String → IO Unit
  | ["derive",source,workspace,output] => PrepareRecordedCorrespondence.derive source workspace output
  | ["publish",source,derivation,output] => PrepareRecordedCorrespondence.publish source derivation output
  | ["publish-project",project,derivation,output] => PrepareRecordedCorrespondence.publishProject project derivation output
  | _ => throw (IO.userError "PrepareRecordedCorrespondence derive SOURCE WORKSPACE OUTPUT | publish SOURCE DERIVATION OUTPUT")
