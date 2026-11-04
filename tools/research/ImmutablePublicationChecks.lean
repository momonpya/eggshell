import Main

open Lean Eggshell
namespace Eggshell.Research.ImmutablePublicationChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def rejects (action : IO Unit) : IO Bool := do
  try action; return false catch _ => return true

def waitFlag (flag : IO.Promise Bool) (deadline : Nat) : IO Unit := do
  repeat
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "publication barrier expired")
    if ← flag.isResolved then return
    IO.sleep 1
  throw (IO.userError "unreachable publication barrier")

def audit (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh immutable publication fixture required"
  FileSystem.privateDirectory root
  let path := root/"same-object"
  let bytes := "same exact immutable bytes".toUTF8
  let installed ← IO.Promise.new
  let release ← IO.Promise.new
  let deadline := (← IO.monoMsNow)+10000
  let writer ← IO.asTask (FileSystem.immutableBytesWith path bytes fun phase => do
    if phase == .installed then
      installed.resolve true
      waitFlag release deadline) .dedicated
  try
    waitFlag installed deadline
    let held ← FileSystem.openRead path.toString
    let first ← FileSystem.readVersion held
    IO.sleep 2
    release.resolve true
    IO.ofExcept (← IO.wait writer)
    let after ← FileSystem.readVersion held
    check (first != after &&
      !FileSystem.publicationAgreement first after after bytes bytes)
      "actual hard-link cleanup did not expose the previous false rejection"
    let current := do FileSystem.readVersion (← FileSystem.openRead path.toString)
    FileSystem.verifyImmutable path held first bytes current
    FileSystem.immutableExistingBytes path bytes
    check (← rejects (FileSystem.verifyImmutable path held after "diff exact immutable bytes".toUTF8 current))
      "different immutable bytes were accepted"
    -- Replace the name with equal bytes while retaining the original descriptor.
    -- A retry must never adopt the replacement inode, even with equal contents.
    FileSystem.atomicExistingBytes path bytes
    check (← rejects (FileSystem.verifyImmutable path held after bytes current))
      "retry adopted a replacement namespace object"
    let fresh ← FileSystem.openRead path.toString
    FileSystem.verifyImmutable path fresh (← FileSystem.readVersion fresh) bytes current
    for iteration in [:4] do
      let shared := root/s!"simultaneous-{iteration}"
      let tasks ← (List.range 80).toArray.mapM fun _ =>
        IO.asTask (FileSystem.immutableExistingBytes shared bytes) .dedicated
      for task in tasks do IO.ofExcept (← IO.wait task)
      check ((← FileSystem.boundedBytes shared 1024) == bytes) "parallel publication changed exact bytes"
    let result := Json.mkObj [("oldPredicateRejectedWinnerCleanup",toJson true),
      ("sameHeldDescriptorRecovered",toJson true),("replacementInodeRejected",toJson true),
      ("differentBytesRejected",toJson true),("parallelIdenticalPublications",toJson (320 : Nat)),
      ("extraGlobalLockOrCAS",toJson false),("adopted",toJson false)]
    IO.FS.writeFile (root/"report.json") (result.pretty++"\n")
    IO.println result.compress
  finally
    unless ← release.isResolved do release.resolve true
    let _ ← IO.wait writer
    pure ()

def createResult (path : System.FilePath) (authority : String) : IO Json := do
  try
    let source ← DB.PageMap.create path authority
    check (source.head.authority == authority && source.head.revision == 0) "fresh DB changed its authority"
    return Json.mkObj [("created",toJson true),("identity",toJson source.head.identity)]
  catch error => return Json.mkObj [("created",toJson false),("error",toJson error.toString)]

/-- Exercise actual exclusive creation, rather than assuming distinct clock
values or inferring ownership from an earlier absence probe. -/
def allocation (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh allocation fixture required"
  FileSystem.privateDirectory root
  let shared := root/"same-target"
  let tasks ← (List.range 80).toArray.mapM fun _ =>
    IO.asTask (createResult shared "same-authority") .dedicated
  let results ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
  check ((results.filter (fun row => row.getObjValD "created" == toJson true)).size == 1)
    "concurrent DB creation did not have exactly one winner"
  let rejected := results.filter (fun row => row.getObjValD "created" != toJson true)
  check (rejected.all fun row =>
    let error := (row.getObjValAs? String "error").toOption.getD ""
    error == "memory DB already exists" ||
      (error.contains "cannot exclusively publish database" && error.contains "File exists"))
    "same-target creation failed for an unexpected reason"
  let winner ← DB.PageMap.pin shared
  check (winner.head.authority == "same-authority" && winner.head.revision == 0)
    "losing creator changed the winning DB"
  let independent ← (List.range 80).toArray.mapM fun index => IO.asTask
    (createResult (root/s!"independent-{index}") s!"authority-{index}") .dedicated
  for task in independent do
    let result ← IO.ofExcept (← IO.wait task)
    check (result.getObjValD "created" == toJson true) "independent creator failed"
  let entries ← root.readDir
  check (!(entries.any fun entry => entry.fileName.startsWith ".eggshell-create-" ||
    FileSystem.isPublicationTemporary entry.fileName)) "finished creator left a staging directory"
  let result := Json.mkObj [("sameTargetRequests",toJson (80 : Nat)),("winners",toJson (1 : Nat)),
    ("explicitRejections",toJson rejected.size),("independentCreations",toJson (80 : Nat)),
    ("winnerUnchanged",toJson true),("stagingDirectoriesLeft",toJson (0 : Nat)),
    ("extraGlobalLockOrCAS",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root/"allocation.json") (result.pretty++"\n")
  IO.println result.compress

end Eggshell.Research.ImmutablePublicationChecks
