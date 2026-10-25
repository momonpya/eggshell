import PartitionBuild
import Eggshell.Install
import Eggshell.KeyedSearchProvider
import Lean

namespace Eggshell.PartitionNativeAudit
open Lean DB Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

run_meta do
  for name in #[``PartitionBuild.share_le_total,``VectorPartition.training_preserves_samples,
      ``VectorPartition.node_roundtrip,``KeyedProtocol.scoped_choice_in_original_array,
      ``KeyedSearchProvider.canonical_windows_preserved,``KeyedSearchProvider.canonical_original_identities] do
    for dependency in ← Lean.collectAxioms name do
      unless #[``propext,``Classical.choice,``Quot.sound].contains dependency do
        throwError "Unapproved live-partition proof dependency: {name}: {dependency}"
  logInfo "Partition source scope, sample preservation, codec and quota checked"

def stage (installPath : System.FilePath) : IO Unit := do
  check installPath.isAbsolute "absolute research prefix required"
  let layout := Install.Layout.at installPath
  check (!(← layout.executable.pathExists)) "preserve staged runtime"
  Install.copyExecutable (← IO.appPath) layout.executable
  IO.FS.createDirAll (layout.plugin / ".codex-plugin")
  IO.FS.createDirAll (layout.plugin / "hooks")
  IO.FS.writeFile (layout.plugin / Install.ownerMarkerName) Install.ownerMarkerContents
  IO.FS.writeFile (layout.plugin / ".codex-plugin/plugin.json") Install.pluginManifest
  IO.FS.writeFile (layout.plugin / "hooks/hooks.json") Install.hooksManifest
  Install.writeExecutable layout.launcher Install.commandLauncher
  for name in ["egg","eggshelld"] do
    Install.writeExecutable (layout.plugin / "bin" / name) (Install.pluginLauncher installPath)

private def publish (source : Snapshot) (values : List Value) : IO Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let roots ← values.mapM intern.root
    writeChange writer ⟨roots,[],false⟩
  PageMap.pin source.directory

private def outcome (index : Nat) : IO Value :=
  IO.ofExcept (Plugin.relation? .outcome [
    .semantic (.text s!"partition fixture question {index}"),
    .semantic (.text s!"partition original observed value {index}")])

private def vectors (root : System.FilePath) (source : Snapshot) :
    IO (VectorMatrix.Ready × VectorBlocks.Ready) := do
  FileSystem.privateDirectory root
  let _ ← CandidateDomain.refresh source .user
  let some domain ← CandidateDomain.openShared? source | throw (IO.userError "fixture domain missing")
  let keys := hashDistinct (domain.documents.flatMap (·.windows))
  let model := "partition-scope-fixture"
  let encoder := "original-synthetic-bits"
  let _ ← VectorMatrix.ensureUsing root model encoder keys fun key =>
    pure ⟨key,"fixture","000000000000f03f0000000000000000"⟩
  let some matrix ← VectorMatrix.open? root model encoder | throw (IO.userError "fixture matrix unavailable")
  let _ ← VectorRoute.refresh root model encoder matrix
  let some route ← VectorRoute.open? root model encoder matrix | throw (IO.userError "fixture physical layout unavailable")
  let _ ← VectorBlocks.prepare root model encoder matrix route
  let some blocks ← VectorBlocks.open? root model encoder matrix route | throw (IO.userError "fixture blocks unavailable")
  return (matrix,blocks)

def fixture (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve the earlier native-partition fixture"
  FileSystem.privateDirectory output
  let keyA := Sha256.hex "canonical-first".toUTF8
  let keyB := Sha256.hex "canonical-later".toUTF8
  let a : KeyedProtocol.Choice := ⟨1,9,4,7,[⟨17,keyB⟩,⟨5,keyA⟩]⟩
  let b : KeyedProtocol.Choice := ⟨0,9,5,1,[⟨0,keyA⟩]⟩
  let [first,second] := KeyedSearchProvider.canonical [a,b] |
    throw (IO.userError "canonical source ordering lost an owner")
  check (first == b && second == {a with windows := [⟨5,keyA⟩,⟨17,keyB⟩]})
    "source/window ties followed nomination order"
  let base ← PageMap.create (output / "source.egg")
    (Persistence.valueToJson (.text "partition-fixture-original-authority")).compress
  let source ← publish base (← (List.range 65).mapM outcome)
  let root := output / "vectors"
  let model := "partition-scope-fixture"
  let encoder := "original-synthetic-bits"
  let (matrix,blocks) ← vectors root source
  check ((← PartitionBuild.open? root model encoder source matrix blocks).isNone &&
    !(← (PartitionBuild.folder root model encoder).pathExists)) "cold query created or accepted an index"
  let first ← PartitionBuild.prepare root model encoder source matrix blocks
  let some old ← PartitionBuild.open? root model encoder source matrix blocks |
    throw (IO.userError "new fixture partition missing")
  let repeated ← PartitionBuild.prepare root model encoder source matrix blocks
  check (first.mode == "prepared" && repeated.mode == "warm" && repeated.writtenBytes == 0)
    "unchanged partition was rebuilt"
  let query := #[[1.0,0.0].toFloatArray]
  old.snapshot.reads.set 0
  let zero ← VectorPartition.nominate old query 0
  check (zero.val.keys.isEmpty && zero.val.visitedCells == 0 && (← old.snapshot.reads.get) == 0)
    "zero source allowance read a centroid"
  let before ← VectorPartition.nominate old query 4096
  check (before.val.keys.length == old.header.basis.rows) "fixture did not expose every eligible original"
  let _ ← PageMap.withWriter source fun writer => do
    writer.put "memo:neutral-probe" (some (ByteArray.mk #[7]))
    writeChange writer ⟨[],[],false⟩
  let neutral ← PageMap.pin source.directory
  let kept ← PartitionBuild.open? root model encoder neutral matrix blocks
  check (kept.isSome && (kept.map (·.snapshot.head)) == some old.snapshot.head)
    "authenticated neutral publication discarded its model"
  let changed ← publish neutral [← outcome 100]
  check ((← PartitionBuild.open? root model encoder changed matrix blocks).isNone)
    "new original owner was hidden behind an older partition"
  let (newMatrix,newBlocks) ← vectors root changed
  let replaced ← PartitionBuild.prepare root model encoder changed newMatrix newBlocks
  let some newer ← PartitionBuild.open? root model encoder changed newMatrix newBlocks |
    throw (IO.userError "replacement partition missing")
  let after ← VectorPartition.nominate newer query 4096
  let pinned ← VectorPartition.nominate old query 4096
  check (replaced.mode == "replaced" && pinned.val.keys == before.val.keys &&
    after.val.keys.length > before.val.keys.length &&
    before.val.keys.all after.val.keys.contains) "replacement lost old pinned or new original keys"
  let foreign ← PageMap.create (output / "foreign.egg") source.head.authority
  check ((← PartitionBuild.open? root model encoder foreign newMatrix newBlocks).isNone)
    "foreign DB reused another original domain"
  let mut allocations := 0
  for count in [1:65] do
    for total in [0,1,7,4096] do
      let shares := (List.range count).map (PartitionBuild.share total count)
      check (shares.sum == total && shares.all (· ≤ total)) "source budgets exceeded or lost the global bound"
      allocations := allocations+1
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("originalKeys",toJson before.val.keys.length),("updatedKeys",toJson after.val.keys.length),
    ("coldDoesNotPrepare",toJson true),("unchangedNoWrite",toJson true),
    ("neutralPublicationReused",toJson true),("changedOriginalUnavailable",toJson true),
    ("oldPinnedPreserved",toJson true),("foreignDbRejected",toJson true),
    ("originalTieOrder",toJson true),("zeroAllowanceNoRead",toJson true),
    ("budgetCases",toJson allocations),("modelCalls",toJson (0 : Nat))]).pretty

end Eggshell.PartitionNativeAudit
