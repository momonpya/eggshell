import Eggshell.ProjectPublication
open Lean Eggshell Eggshell.DB Eggshell.ProjectStore

namespace SourceSnapshotChecks
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def refused (action : IO α) : IO Bool := do
  try discard action; return false
  catch _ => return true

def samePrefix (left right : PageMap.Snapshot) : IO Nat := do
  check (left.head == right.head) "captured source head changed"
  check ((← FileSystem.readVersion right.handle).bytes == left.head.bytes)
    "captured source includes an uncommitted or later tail"
  let mut offset := 0
  while offset < left.head.bytes do
    let count := captureCount left.head.bytes offset
    let leftBytes ← FileSystem.readPage left.handle offset.toUInt64 ⟨count,Nat.min_le_left _ _⟩
    let rightBytes ← FileSystem.readPage right.handle offset.toUInt64 ⟨count,Nat.min_le_left _ _⟩
    check (leftBytes.size == count && leftBytes == rightBytes) "captured native page bytes differ"
    offset := offset+count
  return offset

def run (root report : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists) && !(← report.pathExists)) "fresh native fixture required"
  IO.FS.createDirAll root
  let source ← PageMap.create (root/"source.egg") "arbitrary original authority 日本語"
  let binary := ByteArray.mk (Array.range 1536 |>.map (fun i => UInt8.ofNat (i%256)))
  let text := "原文\nUTF-8 evidence\n\u0000tail".toUTF8
  discard <| PageMap.withWriter source fun writer => do
    writer.put "binary" (some binary)
    writer.put "text" (some text)
    for index in [:12] do writer.put s!"row-{index}" (some binary)
  let capturedBasis ← PageMap.pin source.directory
  discard <| PageMap.withWriter capturedBasis fun writer => do
    writer.put "text" (some "later source state".toUTF8)
    writer.put "only-later" (some "must not be captured".toUTF8)
  let relocated := root/"relocated.egg"
  IO.FS.rename source.directory relocated
  let later ← PageMap.pin relocated
  let beforeHead ← IO.FS.readBinFile (relocated/"head")
  let beforePages ← IO.FS.readBinFile (PageMap.dataPath relocated later.head)
  let project ← capturePinned capturedBasis (root/"snapshot.egg")
  let captured ← project.current 0
  let copied ← samePrefix capturedBasis captured
  check ((← captured.get "binary") == some binary && (← captured.get "text") == some text &&
    (← captured.get "only-later").isNone) "capture did not preserve the pinned original values"
  check (!project.manifest.writable && project.manifest.kind == .snapshot &&
    project.manifest.identity != captured.head.identity && project.manifest.authority == captured.head.authority)
    "source identity or project write authority was fabricated"
  let view ← pin project ((← IO.monoMsNow)+5000)
  check (view.cut.heads == #[capturedBasis.head] && view.sources.size == 1)
    "read-only source did not produce its exact complete cut"
  let some scope ← ProjectCacheScope.at? captured | throw (IO.userError "captured project cache was not found")
  check (scope.root == project.directory && scope.scope.identity == project.manifest.identity &&
    !(← (project.directory/"cache-scope").pathExists)) "cache membership did not use the single manifest"
  let ownerDenied ← refused (acquireOwner project 0)
  check (ownerDenied && !(← (project.ownerDirectory 0/"owner.guard").pathExists))
    "captured input acquired a source writer lease"
  let pool ← Plugin.Publication.Owned.Pool.new
  let writeDenied ← refused (pool.register project.directory project.manifest.identity)
  let readGrant ← pool.registerRead project.directory project.manifest.identity
  let readCut ← pool.pinRead readGrant.manifest.identity readGrant.capability ((← IO.monoMsNow)+5000)
  check (writeDenied && readCut == view.cut) "snapshot service authority is not read-only"
  check (!(project.manifest.accepts 0 later.head) && !(project.manifest.accepts 1 captured.head) &&
    !({view.cut with heads := #[later.head]} : Cut).inScope project.manifest)
    "snapshot accepted a different head or missing owner"
  let altered := {captured.head with revision := captured.head.revision+1}
  FileSystem.atomicBytes (captured.directory/"head") (toJson altered).compress.toUTF8
  let changedHeadDenied ← refused (project.current 0)
  FileSystem.atomicBytes (captured.directory/"head") (toJson captured.head).compress.toUTF8
  check changedHeadDenied "physical snapshot head mutation was accepted"
  let existingDenied ← refused (capturePinned capturedBasis project.directory)
  let nestedDenied ← refused (capture later.directory (later.directory/"nested.egg"))
  check (existingDenied && nestedDenied && !(← (later.directory/"nested.egg").pathExists))
    "capture overwrote an existing target or wrote inside its input"
  check ((← IO.FS.readBinFile (relocated/"head")) == beforeHead &&
    (← IO.FS.readBinFile (PageMap.dataPath relocated later.head)) == beforePages)
    "capture or authority checks modified the native input"
  IO.FS.removeDirAll relocated
  check ((← (← project.current 0).get "text") == some text) "capture depended on the later source pathname"
  let managed ← create (root/"managed.egg") 2
  let owner ← acquireOwner managed 0
  owner.close
  let managedView ← pin managed ((← IO.monoMsNow)+5000)
  check (managed.manifest.writable && managedView.sources.size == 2 &&
    !(← (managed.directory/"cache-scope").pathExists)) "managed project behavior regressed"
  let broken ← PageMap.create (root/"truncated.egg") "truncated original"
  IO.FS.writeBinFile (PageMap.dataPath broken.directory broken.head) ByteArray.empty
  let truncatedDenied ← refused (capturePinned broken (root/"must-not-publish.egg"))
  let remnants ← root.readDir
  check (truncatedDenied && !(← (root/"must-not-publish.egg").pathExists) &&
    !(remnants.any (·.fileName.startsWith ".snapshot-"))) "failed capture published a partial input or leaked staging"
  IO.FS.writeFile report (Json.mkObj [
    ("pinnedHead",toJson capturedBasis.head),("laterHead",toJson later.head),("copiedBytes",toJson copied),
    ("exactNativePrefix",toJson true),("oldPinnedDescriptorAfterRename",toJson true),
    ("laterTailExcluded",toJson true),("arbitraryAuthorityPreserved",toJson true),
    ("singleManifestCacheScope",toJson true),("sourceFilesUnchanged",toJson true),
    ("independentAfterSourceRemoval",toJson true),("sourceWriterDeniedBeforeLease",toJson ownerDenied),
    ("servicePublicationDenied",toJson writeDenied),("serviceReadCutExact",toJson true),
    ("changedPhysicalHeadDenied",toJson changedHeadDenied),("managedProjectRetained",toJson true),
    ("existingAndNestedTargetsDenied",toJson true),("truncatedCaptureDrained",toJson truncatedDenied),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end SourceSnapshotChecks

def main : List String → IO UInt32
  | ["checks",root,report] => do SourceSnapshotChecks.run (.mk root) (.mk report); return 0
  | _ => throw (IO.userError "SourceSnapshotChecks checks FRESH-ROOT NEW-REPORT")
