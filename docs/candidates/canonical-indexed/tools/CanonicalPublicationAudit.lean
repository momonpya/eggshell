import Eggshell.SynapseIndex
open Lean Eggshell

def main (arguments : List String) : IO Unit := do
  let [specification, trialRoot, destination] := arguments |
    throw (IO.userError "CanonicalPublicationAudit FROZEN-SPEC TRIAL-ROOT REPORT")
  let values ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= Json.getArr?)
  let mut results := #[]
  let mut accepted := true
  for value in values do
    let stage ← IO.ofExcept (value.getObjValAs? Nat "stage")
    let path ← IO.ofExcept (value.getObjValAs? String "source")
    let files ← IO.ofExcept (value.getObjValAs? (Array (String × String)) "files")
    let before ← DB.PageMap.pin (.mk path)
    let after ← DB.PageMap.pin (System.FilePath.mk trialRoot / s!"stage{stage}" / "work.egg")
    let same ← Synapses.Index.sameSources after before.head (after.head.revision-before.head.revision+1)
    let original ← IO.FS.readBinFile (DB.PageMap.dataPath before.directory before.head)
    let current ← IO.FS.readBinFile (DB.PageMap.dataPath after.directory after.head)
    let pagePrefix := current.extract 0 before.head.bytes == original.extract 0 before.head.bytes
    let mut frozen := true
    for (name,expected) in files do
      let bytes ← IO.FS.readBinFile (before.directory / name)
      frozen := frozen && Sha256.hex bytes == expected
    let good := same && pagePrefix && frozen
    accepted := accepted && good
    let mut sessions := #[]
    for index in [:2] do
      let trial := System.FilePath.mk trialRoot / s!"stage{stage}" / s!"native-{index}"
      let stdout ← IO.FS.readFile (trial / "prompt" / "stdout")
      let reply ← IO.ofExcept (Json.parse stdout)
      let body ← IO.ofExcept (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext"))
      let saved ← IO.FS.readFile (trial / "body.txt")
      let record ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "prompt" / "record.json")))
      let expected ← IO.ofExcept (record.getObjValAs? String "stdoutSha256")
      let bound := body == saved && Sha256.hex stdout.toUTF8 == expected
      accepted := accepted && bound
      let elapsed ← IO.ofExcept (record.getObjValAs? Nat "elapsedMs")
      let incomplete := decide ((body.splitOn "EGGSHELL SEARCH INCOMPLETE").length > 1)
      sessions := sessions.push (Json.mkObj [
        ("session",toJson index),("elapsedMs",toJson elapsed),("actualStdoutBound",toJson bound),
        ("incomplete",toJson incomplete),("bodySha256",toJson (Sha256.hex body.toUTF8))])
    results := results.push (Json.mkObj [
      ("stage",toJson stage),("sameSourceFacts",toJson same),
      ("samePublishedPagePrefix",toJson pagePrefix),("frozenSourceFilesExact",toJson frozen),
      ("before",toJson before.head),("after",toJson after.head),("sessions",toJson sessions)])
    IO.FS.writeFile (.mk destination) (toJson results).compress
  IO.println (Json.mkObj [("stages",toJson results.size),("allSourceFactsAndBytesUnchanged",toJson accepted)]).compress
  unless accepted do throw (IO.userError "source publication audit failed")
