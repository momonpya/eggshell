import tools.DirectoryReads
import Lean.Data.Json

open Lean Eggshell

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

private def reject (action : IO α) (message : String) : IO Unit := do
  let failed ← try let _ ← action; pure false catch _ => pure true
  check failed message

private def command (name : String) (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := name, args}
  unless result.exitCode == 0 do throw (IO.userError (name ++ ": " ++ result.stderr))

private def bytes (directory : FileSystem.ReadDirectory) (name : String) (limit : Nat := 1048576) : IO ByteArray := do
  FileSystem.boundedRead (← FileSystem.openReadAt directory name) limit

private def exercise (root : System.FilePath) : IO Nat := do
  let active := root / "active"
  IO.FS.createDir active
  let content := "original 日本語🐣\n"
  IO.FS.writeFile (active / "value") content
  IO.FS.writeFile (active / "日本語🐣") content
  IO.FS.writeFile (active / "empty") ""
  let directory ← FileSystem.openReadDirectory active.toString
  check ((← bytes directory "value") == content.toUTF8) "directory read changed original bytes"
  check ((← bytes directory "日本語🐣") == content.toUTF8) "Unicode leaf changed bytes"
  check ((← bytes directory "empty" 0).size == 0) "empty bounded read failed"
  check ((← FileSystem.boundedBytes (active / "value") 1048576) == (← bytes directory "value"))
    "absolute and descriptor-relative reads differ"
  reject (bytes directory "value" 1) "size limit was bypassed"
  reject (FileSystem.openReadDirectory (active / "value").toString) "regular file became a directory"
  reject (FileSystem.openReadDirectory "relative") "relative directory was accepted"
  let filesystemRoot ← FileSystem.openReadDirectory "/"
  reject (FileSystem.openReadAt filesystemRoot ".") "root directory accepted a dot leaf"
  for leaf in ["", ".", "..", "sub/value", "/value", "value\x00suffix"] do
    reject (FileSystem.openReadAt directory leaf) "unsafe leaf name was accepted"
  IO.FS.createDir (active / "sub")
  reject (FileSystem.openReadAt directory "sub") "directory leaf became a regular file"
  command "/bin/ln" #["-s", (active / "value").toString, (active / "link").toString]
  reject (FileSystem.openReadAt directory "link") "symbolic-link leaf was followed"
  command "/bin/ln" #["-s", active.toString, (root / "alias").toString]
  reject (FileSystem.openReadDirectory (root / "alias").toString) "symbolic-link directory was followed"
  command "mkfifo" #[(active / "pipe").toString]
  reject (FileSystem.openReadAt directory "pipe") "FIFO was accepted or blocked"
  let handle ← FileSystem.openReadAt directory "value"
  let before ← FileSystem.readVersion handle
  IO.FS.writeFile (active / "value") "changed"
  let after ← FileSystem.readVersion handle
  check (before != after && !FileSystem.stableRead before after after after.bytes)
    "held file lost mutation identity checks"
  -- A held directory continues to name the object that was validated. A
  -- replacement absolute name must not redirect it into another directory.
  IO.FS.rename active (root / "retired")
  IO.FS.createDir active
  IO.FS.writeFile (active / "value") "replacement"
  check ((← bytes directory "value") == "changed".toUTF8) "held directory followed a replacement"
  check ((← FileSystem.boundedBytes (active / "value") 64) == "replacement".toUTF8)
    "absolute read no longer resolves the current name"
  let reads ← DirectoryReads.new
  let missing := root / "later" / "value"
  reject (reads.open missing) "absent directory became readable"
  IO.FS.createDir (root / "later")
  IO.FS.writeFile missing "new"
  reject (reads.open missing) "request's missing-directory view silently changed"
  reads.invalidate missing
  check ((← FileSystem.boundedRead (← reads.open missing) 64) == "new".toUTF8)
    "local write invalidation did not refresh the directory"
  let fresh ← DirectoryReads.new
  check ((← FileSystem.boundedRead (← fresh.open missing) 64) == "new".toUTF8)
    "later request inherited an earlier missing directory"
  pure 25

private def repeatedScope (path : System.FilePath) : IO Unit := do
  let reads ← DirectoryReads.new
  for _ in [:512] do
    check ((← FileSystem.boundedRead (← reads.open path) 64) == "replacement".toUTF8)
      "repeated scoped read changed a byte"

def main : IO UInt32 := IO.FS.withTempDir fun temporary => do
  let root ← IO.FS.realPath temporary
  let checks ← exercise root
  let before := (← (System.FilePath.mk "/dev/fd").readDir).size
  repeatedScope (root / "active/value")
  repeatedScope (root / "active/value")
  let after := (← (System.FilePath.mk "/dev/fd").readDir).size
  check (after == before) "directory/file descriptors leaked beyond the request"
  IO.println (Json.mkObj [("passed", toJson true), ("boundaryChecks", toJson checks),
    ("repeatedReads", toJson (1024 : Nat)), ("fdBefore", toJson before), ("fdAfter", toJson after),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
  pure 0
