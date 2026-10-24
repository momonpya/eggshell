import tools.research.StudyRuntime
import Eggshell.Warm

open Lean Eggshell Eggshell.Research

namespace HookScaleRun

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def directories (path : System.FilePath) : IO (Array String) := do
  if !(← path.pathExists) then return #[]
  return (← path.readDir).map (·.fileName)

private def native (binary output : System.FilePath) (input : Json) : IO (String × Nat × Nat) := do
  IO.FS.createDir output
  let path := output / "stdin.json"
  IO.FS.writeFile path input.compress
  let started ← IO.monoMsNow
  let result ← IO.Process.output {
    cmd := "/bin/sh"
    args := #["-c","exec \"$1\" codex-hook < \"$2\"","hook",binary.toString,path.toString] }
  let elapsed := (← IO.monoMsNow)-started
  IO.FS.writeFile (output / "stdout.json") result.stdout
  IO.FS.writeFile (output / "stderr.txt") result.stderr
  return (result.stdout,result.exitCode.toNat,elapsed)

private def receipt (root : System.FilePath) (previous : Array String) (stdout : String) : IO Json := do
  let current ← directories root
  let mut found := #[]
  for id in current do
    if previous.contains id then continue
    let path := root / id
    if !(← (path / "published.json").pathExists) then continue
    let published ← (← readJson (path / "published.json")).getObjVal? "data" |> IO.ofExcept
    check ((published.getObjValAs? String "output").toOption == some stdout &&
      (published.getObjValAs? Nat "bytes").toOption == some stdout.utf8ByteSize &&
      (published.getObjValAs? String "sha256").toOption == some (Sha256.hex stdout.toUTF8))
      "publication receipt differs from actual stdout"
    let ack ← if ← (path / "ack.json").pathExists then readJson (path / "ack.json") else pure Json.null
    let mut stages := #[]
    for file in ← path.readDir do
      if file.fileName.endsWith ".json" then
        stages := stages.push (Json.mkObj [("name",toJson file.fileName),
          ("bytes",toJson (← file.path.metadata).byteSize),
          ("sha256",toJson (← ArtifactHash.hex file.path))])
    let search ← if ← (path / "search.json").pathExists then
      pure ((← readJson (path / "search.json")).getObjValD "data") else pure Json.null
    found := found.push (Json.mkObj [("search",search),("id",toJson id),("path",toJson path.toString),
      ("published",published),("ack",ack),("stages",toJson stages)])
  check (found.size == 1) "native call did not yield exactly one confirmed stdout receipt"
  return found[0]!

/-- Native stdout, publication ACK and actual owned-manager teardown, without
an answering model or an App Server. First elapsed includes manager startup;
continued elapsed uses the same manager and its acknowledged native history. -/
def run (binary plugin database output : System.FilePath) (pairs : Nat) : IO Unit := do
  check (output.isAbsolute && !(← output.pathExists) && pairs > 0) "new native cohort required"
  IO.FS.createDir output
  let runtimeHash ← ArtifactHash.hex binary
  let source ← DB.PageMap.pin database
  let config := output / "config.toml"
  IO.FS.writeFile config ("default = \"readonly\"\nsemantic_matcher = " ++
    (toJson [binary.toString,"search-provider"]).compress ++
    "\n[eggs]\nscale = " ++ (toJson database.toString).compress ++
    "\n[profiles.readonly]\nread = [\"scale\"]\nhandoff_chars = 120000\n")
  let warm ← Warm.run source [binary.toString,"search-provider"] false
  IO.FS.writeFile (output / "private-warm.json") (toJson warm).compress
  check (warm.after.missing == 0 && warm.after.invalid == 0 && warm.requested == 0)
    "private preparation encoded a source or left incomplete vectors"
  let repeated ← Warm.run source [binary.toString,"search-provider"] false
  IO.FS.writeFile (output / "repeat-warm.json") (toJson repeated).compress
  check (repeated.requested == 0 && repeated.lexical.added == 0 && repeated.lexical.hydrated == 0 &&
    repeated.domain.mode == "warm") "repeat warm was not ready"
  let root ← Paths.dataRoot
  let receipts := root / "receipts"
  let cohort ← Receipt.fresh
  let mut cases := #[]
  for index in [:pairs] do
    let session := s!"practical-scale-{cohort.take 12}-{source.head.identity.take 12}-{index}"
    let question := s!"Find kernel realtime clock observations for monotonic scheduling and elapsed timers, question {index%3+1}."
    let sessionFiles ← Plugin.sessionFiles session
    check (!(← sessionFiles.state.pathExists) && !(← sessionFiles.pending.pathExists))
      "fresh-chat state already exists"
    let beforeManager ← IO.monoMsNow
    let endpoint ← Plugin.Daemon.endpointPath session
    let managed ← StudyRuntime.startManaged binary plugin session endpoint #[
      ("EGGSHELL_CONFIG",some config.toString)]
    let startupMs := (← IO.monoMsNow)-beforeManager
    try
      for phase in ["first","continued"] do
        let label := s!"pair-{index}-{phase}"
        let before ← directories receipts
        let prior ← (Plugin.readJson? sessionFiles.state Plugin.stateJsonDefaults : IO (Option Plugin.ThreadState))
        let historyBefore := (prior.map (·.deliveredGraphs.length)).getD 0
        let input := Json.mkObj [("hook_event_name",toJson "UserPromptSubmit"),
          ("session_id",toJson session),("turn_id",toJson label),
          ("cwd",toJson output.toString),("prompt",toJson question),
          ("_eggshell_config",toJson config.toString)]
        let (stdout,code,hookMs) ← native binary (output / label) input
        let raw := (Json.parse stdout).toOption
        let body := (raw.bind (fun value =>
          (value.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext")).toOption)).getD ""
        IO.FS.writeFile (output / label / "body.txt") body
        let publication ← try receipt receipts before stdout catch error =>
          pure (Json.mkObj [("error",toJson error.toString)])
        let files ← Plugin.sessionFiles session
        let state ← (Plugin.readJson? files.state Plugin.stateJsonDefaults : IO (Option Plugin.ThreadState))
        let search := state.bind (·.lastSearch)
        let complete := ((publication.getObjVal? "published" >>= (·.getObjValAs? Bool "replyComplete")).toOption).getD false
        let original := decide ((body.splitOn "ORIGINAL_CLOCK_BODY_").length > 1)
        let total := hookMs + if phase == "first" then startupMs else 0
        let currentSearch := publication.getObjValD "search"
        let initial := (currentSearch.getObjValAs? Bool "initialSearch").toOption
        let validStratum := if phase == "first" then historyBefore == 0 && initial == some true else initial == some false
        let record := Json.mkObj [("pair",toJson index),("phase",toJson phase),("historyBefore",toJson historyBefore),("validStratum",toJson validStratum),
          ("question",toJson question),("hookMs",toJson hookMs),("startupMs",toJson startupMs),
          ("totalMs",toJson total),("exitCode",toJson code),("replyComplete",toJson complete),
          ("originalBody",toJson original),("bodyBytes",toJson body.utf8ByteSize),
          ("bodySha256",toJson (Sha256.hex body.toUTF8)),("lastOfferedSearch",toJson search),("search",publication.getObjValD "search"),
          ("acknowledgedHistory",toJson (state.map (·.deliveredGraphs.length))),
          ("publication",publication)]
        cases := cases.push record
        IO.FS.writeFile (output / label / "result.json") record.pretty
        IO.FS.writeFile (output / "results.json") (toJson cases).pretty
        IO.eprintln s!"{label}: {total} ms; complete={complete}; original={original}; bytes={body.utf8ByteSize}"
      StudyRuntime.stopManaged managed (output / s!"pair-{index}-shutdown.json")
    finally
      StudyRuntime.abort managed
  check ((← DB.PageMap.pin database).head == source.head) "native read-only cohort changed source head"
  check ((← ArtifactHash.hex binary) == runtimeHash) "runtime changed during native cohort"
  IO.FS.writeFile (output / "summary.json") (Json.mkObj [
    ("scope",toJson "actual UserPromptSubmit, stdout, publication/ACK and owned-manager exit; no answering model or MCP server"),
    ("runtime",toJson binary.toString),("runtimeSha256",toJson runtimeHash),("source",toJson source.head),
    ("pairs",toJson pairs),("cases",toJson cases),("answeringModelCalls",toJson (0 : Nat))]).pretty

end HookScaleRun

def main (args : List String) : IO Unit := do
  let [binary,plugin,database,output,count] := args | throw (IO.userError "HookScaleRun BINARY PLUGIN DB NEW-OUTPUT PAIRS")
  let some pairs := count.toNat? | throw (IO.userError "invalid pair count")
  HookScaleRun.run (.mk binary) (.mk plugin) (.mk database) (.mk output) pairs
