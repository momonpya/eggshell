import Eggshell.SynapseIndex
open Lean Eggshell

/-- A diagnostic may append derived metadata but may not change original
source facts or any published page. Check both against the frozen source. -/
def main (args : List String) : IO Unit := do
  let [specification,root,nativeRoot,destination] := args |
    throw (IO.userError "CanonicalProbePublicationAudit SPEC PROBE-ROOT NATIVE-ROOT OUTPUT")
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= Json.getArr?)
  let mut results := #[]
  for row in cases do
    let stage ← IO.ofExcept (row.getObjValAs? Nat "stage")
    let path := System.FilePath.mk root / s!"probe-stage{stage}"
    if !(← path.pathExists) then continue
    let originalPath ← IO.ofExcept (row.getObjValAs? String "source")
    let before ← DB.PageMap.pin (.mk originalPath)
    let after ← DB.PageMap.pin (path / "work.egg")
    let same ← Synapses.Index.sameSources after before.head (after.head.revision-before.head.revision+1)
    let original ← IO.FS.readBinFile (DB.PageMap.dataPath before.directory before.head)
    let current ← IO.FS.readBinFile (DB.PageMap.dataPath after.directory after.head)
    let prefixExact := current.extract 0 before.head.bytes == original.extract 0 before.head.bytes
    let files ← IO.ofExcept (row.getObjValAs? (Array (String × String)) "files")
    for (name,expected) in files do
      unless Sha256.hex (← IO.FS.readBinFile (before.directory / name)) == expected do
        throw (IO.userError "original frozen source changed")
    let rendered ← IO.ofExcept (Json.parse (← IO.FS.readFile (path / "result.json")))
    let body ← IO.ofExcept (rendered.getObjValAs? String "text")
    let saved ← IO.FS.readFile (path / "body.txt")
    let native ← IO.FS.readFile (System.FilePath.mk nativeRoot / s!"stage{stage}" / "native-0" / "body.txt")
    unless same && prefixExact && body == saved && body == native do
      throw (IO.userError "diagnostic diverged from original source or actual hook payload")
    results := results.push (Json.mkObj [("stage",toJson stage),("sameOriginalFacts",toJson same),
      ("samePublishedPagePrefix",toJson prefixExact),("sameActualHookBody",toJson (body == native)),
      ("bodySha256",toJson (Sha256.hex body.toUTF8)),("before",toJson before.head),("after",toJson after.head)])
  unless results.size == 2 do throw (IO.userError "expected the two diagnosed stages")
  IO.FS.writeFile (.mk destination) (toJson results).compress
  IO.println "two diagnostics preserve original source facts, original pages and actual native payloads"
