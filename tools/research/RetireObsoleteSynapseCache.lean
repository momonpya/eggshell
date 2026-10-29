import Eggshell.SynapseIndex
open Lean Eggshell

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def readJson (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- An offline, bounded-size metadata inspection. It does not call a native
DB writer, warm or an answering model. The retired file is under 300 MiB. -/
private def lookup (bytes : ByteArray) (extent : Nat) (wanted : String) :
    Nat → DB.PageMap.Ref → IO (Option ByteArray)
  | 0,_ => throw (IO.userError "derived metadata tree exceeded its depth")
  | fuel+1,ref => do
    check (0 < ref.bytes && ref.bytes ≤ 65536 && ref.offset+ref.bytes ≤ extent)
      "derived metadata page outside its committed extent"
    let encoded := bytes.extract ref.offset (ref.offset+ref.bytes)
    check (DB.PageMap.digest encoded == ref.checksum) "derived metadata page digest disagrees"
    let page ← IO.ofExcept (DB.PageMap.decode encoded)
    check (DB.PageMap.agrees ref page) "derived metadata page reference disagrees"
    match page with
    | .leaf rows => return (rows.find? (·.1 == wanted)).bind Prod.snd
    | .branch children =>
      let some child := children.find? (fun row => row.first ≤ wanted && wanted ≤ row.last) | return none
      lookup bytes extent wanted fuel child

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private def originalFiles (source : System.FilePath) : IO (Array (String × String)) := do
  let mut found := #[]
  for entry in ← source.readDir do
    if entry.fileName == "head" || entry.fileName.endsWith ".pages" then
      let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",entry.path.toString]}
      check (output.exitCode == 0) "cannot verify original source before cache retirement"
      found := found.push (entry.fileName,(output.stdout.splitOn " ").headD "")
  return found.qsort (fun a b => a.1 < b.1)

def main (args : List String) : IO Unit := do
  check (args == ["retire"]) "explicit obsolete derived-cache retirement required"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let source := study / "study/seed-2/work.egg"
  let head ← readJson (source / "head")
  let identity ← IO.ofExcept (head.getObjValAs? String "identity")
  check (identity == "d6ff6dad444913158edfc86f2a3bd24212835619ec78e5d4da0e3afe1789a812") "wrong original source"
  let cache := source / "derived" / identity / "synapses/recommendations"
  let index : DB.PageMap.Head ← IO.ofExcept (fromJson? (← readJson (cache / "head")))
  check (index.bytes ≤ 300*1024*1024 && index.authority == "advisory:" ++ identity ++ ":recommendations")
    "obsolete-cache inspection scope or size differs"
  let some tree := index.root | throw (IO.userError "empty derived cache")
  let bytes ← IO.FS.readBinFile (cache / (index.identity ++ ".pages"))
  check (bytes.size == index.bytes) "unexpected uncommitted cache bytes"
  let some encoded ← lookup bytes index.bytes "manifest" (tree.height+1) tree |
    throw (IO.userError "derived cache manifest missing")
  let some text := String.fromUTF8? encoded | throw (IO.userError "invalid manifest UTF-8")
  let manifest ← IO.ofExcept (Json.parse text)
  let implementation ← IO.ofExcept (manifest.getObjValAs? String "implementation")
  check (implementation != Synapses.Index.implementation &&
      (manifest.getObjValD "source").getObjValD "identity" == toJson identity)
    "derived cache still belongs to the current verified implementation"
  let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t","+D",cache.toString]}
  check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "derived cache is in use"
  let before ← originalFiles source
  let record : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/query-cache-llvm/retired-obsolete-index.json"
  check (!(← record.pathExists)) "preserve previous obsolete-cache retirement record"
  let report := Json.mkObj [("directory",toJson cache.toString),("index",toJson index),
    ("manifest",manifest),("expectedImplementation",toJson Synapses.Index.implementation),
    ("originalFiles",toJson before),("logicalBytes",toJson index.bytes),
    ("historicalCapturedIndexMayBeUnavailable",toJson true),
    ("rawSourceJournalAndRecordedMetadataRetained",toJson true),
    ("archiveCreated",toJson false),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.createDirAll record.parent.get!
  IO.FS.writeFile record (report.setObjVal! "completed" (toJson false)).pretty
  remove cache
  check ((← originalFiles source) == before) "original source changed during derived-cache retirement"
  IO.FS.writeFile record (report.setObjVal! "completed" (toJson true)).pretty
  IO.println "Retired an unused implementation-mismatched derived index; original source bytes unchanged"
