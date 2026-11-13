import Eggshell.ContentMetadata
import Eggshell.SynapseBuild
import tools.research.RecordedRecoveryContract
import Lean.Data.Json.Parser
open Lean Eggshell Eggshell.ContentCapture Eggshell.Synapses
namespace RecordedRecoveryChecks
def check (valid : Bool) (reason : String) : IO Unit :=
  unless valid do throw (IO.userError reason)
def rejected (action : IO α) : IO Unit := do
  let accepted ← try let _ ← action; pure true catch _ => pure false
  check (!accepted) "foreign recovery was accepted"
def fixtures (directory output : String) : IO Unit := do
  let root := System.FilePath.mk directory
  check (!(← root.pathExists) && !(← System.FilePath.pathExists output)) "fresh recovery fixtures required"
  IO.FS.createDirAll root
  let code := "first_anchor();\n}\n警告(\"é🧠\");\nlast_anchor();\n"
  IO.FS.writeFile (root/"source.cpp") code
  let inputs ← captureInputs root (Json.mkObj [("paths",toJson #["source.cpp"])]) none ((← IO.monoMsNow)+10000)
  check (inputs.record.valid && !inputs.record.closed) "independent original input fixture is invalid"
  let recorded := inputs.record.files.toArray
  let files := recorded.filterMap fun file => file.content.map fun content =>
    (⟨file.relative,content.root,content.bytes⟩ : Synapses.File)
  let raw := (Json.mkObj [("arbitrary",toJson code)]).compress
  let parent : Captured := {
    implementation := Sha256.hex "historical failed capture".toUTF8,
    inputs := #[],complete := false,aliases := #[],failure := some "input-not-captured"}
  let extra ← recoverSaved root parent raw recorded ((← IO.monoMsNow)+10000)
  check (extra.sealed && extra.boundTo parent raw && extra.inputs == recorded && !extra.aliases.isEmpty)
    "failed capture did not recover from its recorded fingerprints"
  check (extra.parentProducer == parent.implementation) "historical producer was replaced"
  check (extra.aliases.any fun alias => alias.line == 2 && code? raw.toList.toArray alias == some "}")
    "recovered repeated punctuation lost its anchored line"
  let database := Sha256.hex "original database".toUTF8
  let doc : Extraction.Document := {
    owner := "v7",work := "v8",source := some raw,workText := some "arbitrary native observation",
    native := true,occurrences := #[⟨"session","turn","native-use"⟩],files}
  let _ ← IO.ofExcept (ContentMetadata.catalogSupplement database doc parent extra)
  check (!(ContentMetadata.catalogSupplement database doc parent {extra with inputs := #[]}).isOk)
    "omitted original input domain was accepted"
  check (!(ContentMetadata.catalogSupplement database {doc with files := #[]} parent extra).isOk)
    "unrecorded file domain was accepted"
  let changedFiles := files.map fun file => {file with fingerprint := Sha256.hex "another file".toUTF8}
  check (!(ContentMetadata.catalogSupplement database {doc with files := changedFiles} parent extra).isOk)
    "foreign original fingerprint was accepted"
  check (!(ContentMetadata.catalogSupplement database {doc with source := some "different output"} parent extra).isOk)
    "foreign original body was accepted"
  let prepared ← DB.PageMap.create (root/"prepared") "advisory recovery fixture"
  let (_,head,_) ← DB.PageMap.withWriter prepared fun writer =>
    ContentMetadata.stageSupplement writer database 7 doc parent extra
  let pin ← DB.PageMap.pin prepared.directory
  let some loaded ← ContentMetadata.loadSupplement? pin database 7 doc parent |
    throw (IO.userError "prepared recovery was lost on reopen")
  check (toJson loaded == toJson extra) "prepared recovery changed during persistence"
  let (_,again,_) ← DB.PageMap.withWriter pin fun writer =>
    ContentMetadata.stageSupplement writer database 7 doc parent extra
  check (again == head) "unchanged recovery republished its derived root"
  rejected (ContentMetadata.loadSupplement? pin database 7 {doc with owner := "v9"} parent)
  rejected (ContentMetadata.loadSupplement? pin database 7 {doc with work := "v10"} parent)
  rejected (ContentMetadata.loadSupplement? pin (Sha256.hex "another database".toUTF8) 7 doc parent)
  rejected (ContentMetadata.loadSupplement? pin database 7 {doc with files := changedFiles} parent)
  IO.FS.writeFile (root/"source.cpp") (code.replace "first_anchor" "other_anchor")
  let changed ← recoverSaved root parent raw recorded ((← IO.monoMsNow)+10000)
  check (!changed.sealed && changed.aliases.isEmpty) "modified input was assigned historical coordinates"
  check ((← DB.PageMap.pin prepared.directory).head == head) "rejected recovery changed prepared state"
  IO.FS.writeFile output (Json.mkObj [("recoveredAliases",toJson extra.aliases.size),
    ("originalProducerPreserved",toJson true),("omittedDomainRejected",toJson true),
    ("unrecordedDomainRejected",toJson true),("foreignFingerprintRejected",toJson true),
    ("foreignBodyRejected",toJson true),("foreignOwnerWorkDatabaseRejected",toJson true),
    ("durableReopen",toJson true),("idempotentRetry",toJson true),("changedInputRejected",toJson true),
    ("certifiedCompletionIntroduced",toJson false),("allPassed",toJson true),("adopted",toJson false)]).compress
end RecordedRecoveryChecks
def main : List String → IO Unit
  | [directory,output] => RecordedRecoveryChecks.fixtures directory output
  | _ => throw (IO.userError "RecordedContentRecoveryChecks NEW-ROOT NEW-OUTPUT")
