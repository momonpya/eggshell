import Eggshell.PublicationClient
import Eggshell.PublicationService
import tools.research.ArtifactHash

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def decodeFrames (frames : Array ByteArray) : IO String := do
  let remaining ← IO.mkRef frames.toList
  Publication.Stream.receiveWith do
    match ← remaining.get with
    | [] => throw (IO.userError "test peer closed the stream")
    | first::rest => remaining.set rest; return first

private def rejected (action : IO String) : IO Bool := do
  try let _ ← action; return false
  catch _ => return true

private def frames (text : String) : IO (Array ByteArray) := do
  let collected ← IO.mkRef #[]
  Publication.Stream.send (fun bytes => collected.modify (·.push bytes)) (.ok text)
  collected.get

private def protocol : IO Json := do
  let large := String.fromUTF8! (ByteArray.mk (Array.replicate (5*Publication.Stream.chunkBytes+31) (34 : UInt8)))
  let unicode := String.ofList (List.replicate 400000 '界')
  let mut checks := #[]
  for text in #["",unicode,large] do
    let sent ← frames text
    check (sent[0]!.size ≤ 4096) "stream header contains payload-sized metadata"
    check ((← decodeFrames sent) == text) "stream changed the full original bytes"
    check (sent.all (fun bytes => bytes.size ≤ Daemon.maxFrameBytes))
      s!"physical frame bound {Daemon.maxFrameBytes}: {(toJson (sent.map ByteArray.size)).compress}"
    checks := checks.push (Json.mkObj [("bytes",toJson text.utf8ByteSize),("frames",toJson sent.size)])
  let sent ← frames large
  check (← rejected (decodeFrames sent.pop)) "truncated stream was accepted"
  let bad := sent.set! 1 (sent[1]!.set! 0 (35 : UInt8))
  check (← rejected (decodeFrames bad)) "corrupt stream was accepted"
  let over := sent.set! (sent.size-1) (sent.back! ++ ByteArray.mk #[0])
  check (← rejected (decodeFrames over)) "overlong stream was accepted"
  let oversized := (Json.mkObj [("ok",toJson true),("bytes",toJson (Publication.Stream.maxBytes+1)),
    ("digest",toJson "unused")]).compress.toUTF8
  check (← rejected (decodeFrames #[oversized])) "oversized declaration was accepted"
  return Json.mkObj [("roundTrips",toJson checks),("truncatedRejected",toJson true),
    ("corruptRejected",toJson true),("overlongRejected",toJson true),("oversizedDeclarationRejected",toJson true)]

def main (args : List String) : IO UInt32 := do
  if args == ["server"] then return ← Publication.Service.run
  let [database,report] := args | throw (IO.userError "DATABASE NEW-REPORT")
  check (!(← (System.FilePath.mk report).pathExists)) "preserve previous source projection evidence"
  let contract ← protocol
  let source ← DB.PageMap.pin (.mk database)
  let some expected ← CanonicalSource.Cache.open? source .database | throw (IO.userError "prepared canonical source required")
  let loaded := CanonicalSource.Shared.Loaded.make expected
  let owners := loaded.owners.toArray.map Prod.fst |>.qsort (· < ·)
  let expectedRows := loaded.rows owners
  let child ← IO.Process.spawn {
    cmd := (← IO.appPath).toString,args := #["server"],stdin := .null,stdout := .inherit,stderr := .inherit,setsid := true}
  let endpointPath := (← Publication.directory) / "endpoint.json"
  let finished ← IO.mkRef false
  try
    let deadline := (← IO.monoMsNow)+10000
    while !(← endpointPath.pathExists) do
      check ((← child.tryWait).isNone && (← IO.monoMsNow) < deadline) "projection service failed before readiness"
      IO.sleep 5
    let endpoint ← IO.ofExcept (Json.parse (← IO.FS.readFile endpointPath) >>= fromJson? (α := Daemon.Endpoint))
    check (endpoint.pid == child.pid.toNat) "projection endpoint belongs to another service"
    let some reference ← Publication.Client.prepareSourceUsing endpoint source .database ((← IO.monoMsNow)+28000) |
      throw (IO.userError "actual prepared source unavailable")
    let started ← IO.monoMsNow
    let result ← Publication.Client.sourceRows reference owners (started+28000)
    let elapsed := (← IO.monoMsNow)-started
    check (result.rows == expectedRows) "streaming changed source rows, code or origin bindings"
    let outputBytes := (toJson result).compress.utf8ByteSize
    let geometryStarted ← IO.monoMsNow
    let geometries ← Publication.Client.sourceRecords reference owners (geometryStarted+28000)
    let geometryMs := (← IO.monoMsNow)-geometryStarted
    check (geometries.rows.map Prod.fst == owners) "streaming changed original recipe owner domain"
    let _ ← Daemon.exchange endpoint "shutdown" Json.null (budget := 1000)
    let code ← child.wait
    finished.set true
    check (code == 0 && !(← endpointPath.pathExists)) "owned projection service failed to exit"
    check ((← DB.PageMap.pin (.mk database)).head == source.head) "projection check wrote the original DB"
    let value := Json.mkObj [("protocol",contract),("owners",toJson owners.size),
      ("rows",toJson (result.rows.foldl (fun count row => count+row.2.size) 0)),
      ("projectionBytes",toJson outputBytes),("exceededOldProjectionWireBound",toJson (decide (outputBytes > (Daemon.maxFrameBytes-4096)/2))),
      ("projectionMs",toJson elapsed),("originalGeometryMs",toJson geometryMs),
      ("originalGeometryBytes",toJson (toJson geometries).compress.utf8ByteSize),
      ("rowsAndBindingsExact",toJson true),("sourceUnchanged",toJson true),
      ("serviceExitCode",toJson code.toNat),("endpointRemoved",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]
    IO.FS.writeFile (.mk report) value.compress
    IO.println value.compress
    return 0
  finally
    if !(← finished.get) then
      try child.kill catch _ => pure ()
      let _ ← child.wait
      pure ()
