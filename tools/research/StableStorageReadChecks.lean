import Main
import Eggshell.ContractAudit
import tools.research.SharedProjectLifecycle
import tools.research.AutomaticPublicationChecks
open Lean Eggshell
run_elab do
  let environment ← Lean.getEnv
  let mut pending := [``Eggshell.FileSystem.boundedRead]
  let mut seen : List Lean.Name := []
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := name :: seen
    for forbidden in [``IO.sleep,``Std.Mutex.atomically,``Std.Mutex.tryAtomically,
        ``Eggshell.FileSystem.tryReadLock,``Eggshell.FileSystem.openRead] do
      if name == forbidden then throwError "Pinned storage read waits, locks, or reopens a path: {name}"
    if name.toString.startsWith "Eggshell.FileSystem." then
      if let some value := (environment.find? name).bind (·.value?) then
        pending := value.getUsedConstants.toList++pending
  for required in [``Eggshell.FileSystem.storageReadAttempt,``Eggshell.FileSystem.checkedStorageImage?,
      ``Eggshell.FileSystem.readVersion,``Eggshell.FileSystem.readPage] do
    unless seen.contains required do throwError "Pinned storage read bypasses {required}"

namespace StableStorageReadChecks
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def failure (action : IO α) : IO String := do
  let error ← try discard <| action; pure none catch error => pure (some error)
  let some error := error | throw (IO.userError "expected a storage failure")
  return toString error
def fingerprints (directory output : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  let mut rows := #[]
  for entry in ← (root/"src").readDir do
    if (← entry.path.symlinkMetadata).type != .file then continue
    let some (content,_) ← SourceEvidence.fingerprint entry.path ((← IO.monoMsNow)+5000) |
      throw (IO.userError "fixture source fingerprint unavailable")
    rows := rows.push (Json.mkObj [("path",toJson ("src/"++entry.fileName)),("content",toJson content)])
  check (rows.size == 16) "all sixteen original source fingerprints required"
  IO.FS.writeFile (.mk output) (toJson rows).pretty
def run (directory output : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  check (root.isAbsolute && !(← root.pathExists)) "fresh native storage fixture required"
  IO.FS.createDirAll root
  let old := (String.ofList (List.replicate 9001 'a')).toUTF8
  let replacement := (String.ofList (List.replicate 9007 'b')).toUTF8
  let stablePath := root/"stable"
  FileSystem.atomicBytes stablePath old
  let stableHandle ← FileSystem.openRead stablePath.toString
  let stableVersions ← IO.mkRef (0 : Nat)
  let stablePages ← IO.mkRef (0 : Nat)
  let stable ← FileSystem.boundedStorageImageWith 3 10000
    (do stableVersions.modify (·+1); FileSystem.readVersion stableHandle)
    (fun offset count => do stablePages.modify (·+1); FileSystem.readPage stableHandle offset count)
  check (stable.bytes == old && (← stableVersions.get) == 2 && (← stablePages.get) == 3)
    "unchanged multi-page storage should be read exactly once"
  check ((← FileSystem.boundedBytes stablePath 10000) == old) "ordinary path reader changed stable bytes"

  let path := root/"atomically-replaced"
  FileSystem.atomicBytes path old
  let handle ← FileSystem.openRead path.toString
  let before ← FileSystem.readVersion handle
  let replaced ← IO.mkRef false
  let versions ← IO.mkRef (0 : Nat)
  let pages ← IO.mkRef (0 : Nat)
  let image ← FileSystem.boundedStorageImageWith 3 10000
    (do versions.modify (·+1); FileSystem.readVersion handle)
    (fun offset count => do
      pages.modify (·+1)
      unless ← replaced.get do
        IO.sleep 5
        FileSystem.atomicExistingBytes path replacement
        replaced.set true
      FileSystem.readPage handle offset count)
  let current ← FileSystem.readVersion (← FileSystem.openRead path.toString)
  check (before != image.before && image.before == image.after) "replacement must invalidate only the first complete attempt"
  check (image.bytes == old && (← versions.get) == 4 && (← pages.get) == 6)
    "replacement must stabilize on the same original descriptor in two attempts"
  check ((← FileSystem.boundedBytes path 10000) == replacement) "new path did not retain its replacement"
  check (!FileSystem.stableRead before image.after current old.size)
    "external source freshness must still reject the replaced original"

  let burstPath := root/"bounded-mutation-burst"
  FileSystem.atomicBytes burstPath "a".toUTF8
  let burstHandle ← FileSystem.openRead burstPath.toString
  let burstPages ← IO.mkRef (0 : Nat)
  let burstVersions ← IO.mkRef (0 : Nat)
  let burst ← FileSystem.boundedStorageImageWith 3 1
    (do burstVersions.modify (·+1); FileSystem.readVersion burstHandle)
    (fun offset count => do
      let step ← burstPages.get
      burstPages.modify (·+1)
      if step < 2 then
        IO.sleep 5
        IO.FS.writeBinFile burstPath (if step == 0 then "b".toUTF8 else "c".toUTF8)
      FileSystem.readPage burstHandle offset count)
  check (burst.bytes == "c".toUTF8 && (← burstVersions.get) == 6 && (← burstPages.get) == 3)
    "a two-change burst must stabilize exactly on the final allowed attempt"

  let changingPath := root/"continuously-changing"
  FileSystem.atomicBytes changingPath "x".toUTF8
  let changingHandle ← FileSystem.openRead changingPath.toString
  let changes ← IO.mkRef (0 : Nat)
  let changingVersions ← IO.mkRef (0 : Nat)
  let changingFailure ← failure (FileSystem.boundedStorageImageWith 3 1
    (do changingVersions.modify (·+1); FileSystem.readVersion changingHandle)
    (fun offset count => do
      changes.modify (·+1)
      IO.sleep 5
      IO.FS.writeBinFile changingPath (if (← changes.get) % 2 == 1 then "y".toUTF8 else "z".toUTF8)
      FileSystem.readPage changingHandle offset count))
  check (changingFailure.contains "did not stabilize" && (← changes.get) == 3 && (← changingVersions.get) == 6)
    "continuous mutation must fail after exactly three attempts"

  let oversizeVersions ← IO.mkRef (0 : Nat)
  let oversizePages ← IO.mkRef (0 : Nat)
  let oversizeFailure ← failure (FileSystem.boundedStorageImageWith 3 1
    (do oversizeVersions.modify (·+1); FileSystem.readVersion stableHandle)
    (fun offset count => do oversizePages.modify (·+1); FileSystem.readPage stableHandle offset count))
  check (oversizeFailure.contains "byte budget" && (← oversizeVersions.get) == 1 && (← oversizePages.get) == 0)
    "an oversized image must fail before page reads or retries"

  let truncatedPath := root/"truncated"
  FileSystem.atomicBytes truncatedPath old
  let truncatedHandle ← FileSystem.openRead truncatedPath.toString
  let truncatedPages ← IO.mkRef (0 : Nat)
  let truncatedFailure ← failure (FileSystem.boundedStorageImageWith 3 10000
    (FileSystem.readVersion truncatedHandle)
    (fun offset count => do
      truncatedPages.modify (·+1)
      IO.FS.writeBinFile truncatedPath ByteArray.empty
      FileSystem.readPage truncatedHandle offset count))
  check (truncatedFailure.contains "truncated" && (← truncatedPages.get) == 1)
    "a truncated read must not become a successful retry"

  let errorPages ← IO.mkRef (0 : Nat)
  let nativeFailure ← failure (FileSystem.boundedStorageImageWith 3 10000
    (FileSystem.readVersion stableHandle)
    (fun _ _ => do errorPages.modify (·+1); throw (IO.userError "injected native read failure")))
  check (nativeFailure.contains "injected native read failure" && (← errorPages.get) == 1)
    "native IO failure must propagate without retry"
  let emptyPath := root/"empty"
  FileSystem.atomicBytes emptyPath ByteArray.empty
  check ((← FileSystem.boundedBytes emptyPath 0).isEmpty) "empty committed metadata should remain readable"

  let result := Json.mkObj [("stableMultiPage",Json.mkObj [("versionCalls",toJson (← stableVersions.get)),
      ("pageCalls",toJson (← stablePages.get)),("bytes",toJson stable.bytes.size)]),
    ("atomicReplacement",Json.mkObj [("firstAttemptWouldBeRejected",toJson (before != image.before)),
      ("pinnedOriginalBytesUnchanged",toJson (image.bytes == old)),("pathHasNewBytes",toJson true),
      ("versionCalls",toJson (← versions.get)),("pageCalls",toJson (← pages.get)),
      ("before",toJson before),("stableBefore",toJson image.before),("stableAfter",toJson image.after),
      ("currentPath",toJson current),("externalFreshnessRejects",toJson true)]),
    ("twoMutationBurst",Json.mkObj [("versionCalls",toJson (← burstVersions.get)),("pageCalls",toJson (← burstPages.get))]),
    ("continuousMutation",Json.mkObj [("versionCalls",toJson (← changingVersions.get)),
      ("pageCalls",toJson (← changes.get)),("error",toJson changingFailure)]),
    ("oversize",Json.mkObj [("versionCalls",toJson (← oversizeVersions.get)),
      ("pageCalls",toJson (← oversizePages.get)),("error",toJson oversizeFailure)]),
    ("truncated",Json.mkObj [("pageCalls",toJson (← truncatedPages.get)),("error",toJson truncatedFailure)]),
    ("nativeIoFailure",Json.mkObj [("pageCalls",toJson (← errorPages.get)),("error",toJson nativeFailure)]),
    ("empty",toJson true),("readLocksAdded",toJson false),("productSleepAdded",toJson false),
    ("hookReplays",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (.mk output) result.pretty
  IO.println result.compress
end StableStorageReadChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["checks",directory,output] => StableStorageReadChecks.run directory output; return 0
  | ["automatic",input,directory] => AutomaticPublicationChecks.run input directory; return 0
  | ["fingerprints",directory,output] => StableStorageReadChecks.fingerprints directory output; return 0
  | _ => sourceRouteEngine args
