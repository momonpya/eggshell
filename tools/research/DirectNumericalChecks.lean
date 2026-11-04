import Main

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.DirectNumericalChecks

def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path (value.compress++"\n")

def closePipe (running : SemanticMatcher.Running) : IO Unit := do
  SemanticMatcher.write running "C\n"
  let deadline := (← IO.monoMsNow)+10000
  repeat
    if let some code ← running.child.tryWait then
      discard <| SemanticMatcher.closeInput running
      check (code == 0) "numerical pipe exited unsuccessfully"
      return
    check ((← IO.monoMsNow) < deadline) "numerical pipe close expired"
    IO.sleep 5
  throw (IO.userError "unreachable pipe close")

def pipeRequest (running : SemanticMatcher.Running) (marker : UInt8) (body : Json) : IO Json := do
  SemanticMatcher.write running ((String.singleton (Char.ofNat marker.toNat))++body.compress++"\n")
  let result ← IO.ofExcept (Json.parse (← SemanticMatcher.readLine running))
  if let .ok error := result.getObjValAs? String "error" then throw (IO.userError error)
  return result

def value (marker : UInt8) (result : Json) : IO Json := do
  if marker == 69 then
    return Json.mkObj [("vectors",← IO.ofExcept (result.getObjVal? "vectors")),
      ("coverage",← IO.ofExcept (result.getObjVal? "coverage"))]
  return ← IO.ofExcept (result.getObjVal? "scores")

def cases : Array (UInt8 × Json) := Id.run do
  let unit := "000000000000f03f"++String.join (List.replicate 383 "0000000000000000")
  let scores := Json.mkObj [("queries",toJson #[unit]),("candidates",toJson #[#[unit]])]
  let blocks := Json.mkObj [("queries",toJson #[unit]),("blockRows",toJson #[BlockScore.Input.projected unit])]
  let large := Json.mkObj [("queries",toJson #[unit]),("candidates",toJson ((List.replicate 1500 #[unit]).toArray))]
  let texts := Json.mkObj [("texts",toJson #["shared numerical ownership","警告と言語の状態を記録する。","커널 분석 café :: llvm::StringRef"])]
  return #[(83,scores),(69,texts),(69,texts),(66,blocks),(83,scores),(83,large)]

def exercise (ask : UInt8 → Json → IO Json) : IO (Array Json × Array Json) := do
  let mut values := #[]
  let mut times := #[]
  for (marker,input) in cases do
    let begun ← IO.monoMsNow
    let result ← ask marker input
    values := values.push (← value marker result)
    times := times.push (Json.mkObj [("marker",toJson marker.toNat),("elapsedMs",toJson ((← IO.monoMsNow)-begun))])
  return (values,times)

def arm (root : System.FilePath) (parent : String) (direct : Bool) (label : String) : IO (Array Json) := do
  let some config ← Numerical.defaultConfig? | throw (IO.userError "installed MiniLM boundary required")
  let started ← IO.monoMsNow
  let (values,times,opened,closed) ← if direct then do
      let client ← Numerical.openClient config
      let opened ← IO.monoMsNow
      try
        let result ← exercise fun marker input => do
          let reply ← IO.ofExcept (Json.parse (← client.request marker input.compress))
          if let .ok error := reply.getObjValAs? String "error" then throw (IO.userError error)
          return reply
        let begun ← IO.monoMsNow
        client.close
        client.close
        let rejected ← try
          let _ ← client.request 69 "{}"
          pure false
          catch error => pure (error.toString.contains "closed")
        check rejected "a closed client admitted another request"
        pure (result.1,result.2,opened-started,(← IO.monoMsNow)-begun)
      finally client.close
    else do
      let pipe ← SemanticMatcher.start [parent,"codex-numerical-client",config.model,config.models.toString,config.python.toString]
      let opened ← IO.monoMsNow
      try
        let result ← exercise (pipeRequest pipe)
        let begun ← IO.monoMsNow
        closePipe pipe
        pure (result.1,result.2,opened-started,(← IO.monoMsNow)-begun)
      finally SemanticMatcher.stop pipe false
  save (root/(label++".json")) (Json.mkObj [("direct",toJson direct),("openMs",toJson opened),
    ("operations",toJson times),("closeMs",toJson closed),("totalMs",toJson ((← IO.monoMsNow)-started)),
    ("valueSha256",toJson (Sha256.hex (toJson values).compress.toUTF8))])
  return values

def ownership (root : System.FilePath) : IO Unit := do
  let some config ← Numerical.defaultConfig? | throw (IO.userError "installed MiniLM boundary required")
  check ((← Numerical.endpoint? config).isNone) "a prior component arm retained its numerical service"
  let first ← Numerical.openClient config
  let second ← Numerical.openClient config
  try
    let (scoreMarker,scoreInput) := cases[0]!
    let _ ← first.request scoreMarker scoreInput.compress
    check ((← Numerical.endpoint? config).isNone && (← first.shared.get).isNone)
      "cache-only local scoring started an embedding service"
    let invalid ← try
      let _ ← first.request 67 "{}"
      pure false
      catch error => pure (error.toString.contains "invalid")
    check invalid "close marker was admitted as a numerical request"
    let (marker,input) := cases[1]!
    let before ← first.request marker input.compress
    let some endpoint ← Numerical.endpoint? config | throw (IO.userError "embedding did not create a numerical service")
    first.close
    check (← Numerical.alive endpoint.pid) "one client stopped another owner's service"
    let after ← second.request marker input.compress
    check ((← value marker (← IO.ofExcept (Json.parse before))) ==
      (← value marker (← IO.ofExcept (Json.parse after)))) "a surviving owner changed vectors or coverage"
    let some same ← Numerical.endpoint? config | throw (IO.userError "surviving owner lost its endpoint")
    check (same.pid == endpoint.pid) "surviving owner started another model service"
    second.close
    check ((← Numerical.endpoint? config).isNone && !(← Numerical.alive endpoint.pid))
      "last owner left its numerical service live"
    save (root/"ownership.json") (Json.mkObj [("cacheOnlyNoModel",toJson true),
      ("invalidMarkerRejected",toJson true),("survivingOwnerSameServiceAndValues",toJson true),
      ("lastOwnerStoppedService",toJson true),("closedClientRejected",toJson true)])
  finally
    first.close
    second.close

def components (root : System.FilePath) (parent : String) : IO Unit := do
  check (!(← root.pathExists)) "preserve prior component evidence"
  IO.FS.createDir root
  let largeBytes := cases.back!.2.compress.utf8ByteSize
  check (largeBytes > Daemon.maxFrameBytes) "large local score input does not exceed the RPC bound"
  let mut expected : Option (Array Json) := none
  for repetition in [:3] do
    for direct in (if repetition % 2 == 0 then [false,true] else [true,false]) do
      let values ← arm root parent direct s!"pair-{repetition}-{if direct then "direct" else "pipe"}"
      let scores ← IO.ofExcept (fromJson? values.back! : Except String (Array Float))
      check (scores.size == 1500 && scores.all (· == 1.0)) "large local score frame changed unit-vector products"
      if let some prior := expected then check (values == prior) "pipe/direct numerical values changed"
      else
        expected := some values
        save (root/"frozen-values.json") (toJson values)
  ownership root
  save (root/"report.json") (Json.mkObj [("allPassed",toJson true),("matchedPairs",toJson (3 : Nat)),
    ("largeLocalFrameBytes",toJson largeBytes),("largeLocalScores",toJson (1500 : Nat)),
    ("allVectorsCoverageAndScoresIdentical",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def replay (root : System.FilePath) (parent : String) (retained : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve prior replay evidence"
  IO.FS.createDir root
  let project ← ProjectStore.openProject (retained/"work.project")
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let inputs ← view.sources.mapM fun source => do
    let some input ← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "retained exact source inputs are not prepared")
    return input
  let some owners ← OwnerViews.load? view.sources | throw (IO.userError "retained complete owner inputs are not prepared")
  let question := "Return the recorded support seed alpha and tail facts."
  let request : KeyedProtocol.Request := ⟨question,view.sources.map KeyedProtocol.Scope.ofSnapshot,4096,8192,none,some inputs,some owners⟩
  save (root/"frozen-request.json") (toJson request)
  let current := (← IO.appPath).toString
  let mut expected : Option Json := none
  let mut times := #[]
  for repetition in [:3] do
    for direct in (if repetition % 2 == 0 then [false,true] else [true,false]) do
      let binary := if direct then current else parent
      let begun ← IO.monoMsNow
      let result ← SemanticMatcher.withProvider [binary,"keyed-search-provider"] fun running =>
        SemanticMatcher.withResponseDeadline running (do
          SemanticMatcher.write running ((toJson request).compress++"\n")
          IO.ofExcept (Json.parse (← running.child.stdout.getLine)))
      let elapsed := (← IO.monoMsNow)-begun
      if let .ok error := result.getObjValAs? String "error" then throw (IO.userError error)
      let response ← IO.ofExcept (fromJson? result : Except String KeyedProtocol.Response)
      let checked ← IO.ofExcept (KeyedProtocol.check view.sources response)
      KeyedProtocol.validateRelated view.sources checked
      if let some prior := expected then check (result == prior) "full keyed response changed across runtimes"
      else expected := some result
      let label := s!"pair-{repetition}-{if direct then "direct" else "pipe"}"
      save (root/(label++".json")) result
      times := times.push (Json.mkObj [("arm",toJson label),("elapsedMs",toJson elapsed),
        ("responseSha256",toJson (Sha256.hex result.compress.toUTF8))])
  for source in view.sources do
    check ((← DB.PageMap.pin source.directory).head == source.head) "provider replay changed an original source head"
  save (root/"report.json") (Json.mkObj [("allPassed",toJson true),("fullResponsesIdentical",toJson true),
    ("sourceHeadsUnchanged",toJson true),("timings",toJson times),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

end Eggshell.Research.DirectNumericalChecks
