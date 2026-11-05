import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction
namespace Eggshell.Research.PublicPreparationChecks

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)
private def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path (value.pretty++"\n")
private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def events (source : DB.PageMap.Snapshot) (tool : ToolEvent)
    (session turn : String) (ordinal : Nat) : IO (Array Journal.Entry) := do
  let occurrence : Occurrence := ⟨session,turn,tool.useId⟩
  let known ← Journal.knowledge source [] false
  let clock := Sha256.hex (session++":"++turn).toUTF8
  return #[⟨⟨clock,ordinal*2+1⟩,.start occurrence (canonicalToolWork tool) (Sha256.hex "fixed query".toUTF8) known,none⟩,
    ⟨⟨clock,ordinal*2+2⟩,.finish occurrence tool.name (canonicalJson tool.input)
      (canonicalJson tool.response) (some source.directory.toString),none⟩]

private def publish (source : DB.PageMap.Snapshot) (root : System.FilePath) (tool : ToolEvent)
    (session turn : String) (ordinal : Nat) : IO (DB.PageMap.Snapshot × Array Journal.Entry) := do
  let values ← events source tool session turn ordinal
  for value in values do discard <| Journal.append source value
  let pending : PendingTurn := {
    sessionId := session,turnId := turn,cwd := root.toString,prompt := "fixed query",profile := "work",
    write := some source.directory.toString,read := [],semanticMatcher := none,handoffChars := 120000,
    projection := .none,tools := [tool]}
  let _ ← NativePublication.run pending source.directory true
  return (← DB.PageMap.pin source.directory,values)

private def tool (root : System.FilePath) (size : Nat) : IO ToolEvent := do
  if size == 0 then
    IO.FS.writeFile (root/"specimen.c") "int alpha = 1;\nint beta = 2;\n"
    let input := Json.mkObj [("command",toJson "nl -ba specimen.c | sed -n '1,2p'")]
    let capture ← SourceEvidence.capture root input ((← IO.monoMsNow)+10000)
    let response := (Json.mkObj [("output",toJson "1\tint alpha = 1;\n2\tint beta = 2;\n")]).compress
    let correspondence ← ContentCapture.finish root capture response ((← IO.monoMsNow)+10000)
    return {
      name := "arbitrary_reader",useId := "read",input := input.compress,response
      source := some capture,correspondence := some correspondence}
  let filler := String.ofList (List.replicate size 'z')
  return {
    name := "mcp__fixture__lookup",useId := "read",input := "{\"ticket\":42}"
    response := (Json.mkObj [("symbol",toJson "alpha"),("payload",toJson filler)]).compress}

private def makeFixture (root : System.FilePath) (size : Nat) : IO Json := do
  IO.FS.createDirAll root
  let input ← tool root size
  let inspect : ToolEvent := {
    name := "mcp__fixture__inspect",useId := "inspect"
    input := "{\"identifier\":\"alpha\"}",response := "{}"}
  let empty ← Persistence.ensureSnapshot (root/"source.egg")
  let (seed,seedEvents) ← publish empty root input "session" "seed" 0
  let (middle,first) ← publish seed root input "session" "analysis" 0
  let (source,second) ← publish middle root inspect "session" "analysis" 1
  return Json.mkObj [("directory",toJson source.directory.toString),("head",toJson source.head),
    ("seed",toJson seedEvents),("analysis",toJson (first++second)),("size",toJson size)]

private def sameFacts (left right : Array Fact) : Bool :=
  left.all right.contains && right.all left.contains
private def consumed (facts : Array Fact) : Array Fact :=
  facts.filter fun fact => match fact with | .consumed _ => true | _ => false
private def shared (source : DB.PageMap.Snapshot) : IO Index.Reader := do
  let some reader ← Index.open? source .database .shared | throw (IO.userError "missing prepared shared source")
  return reader

private def observe (root : System.FilePath) (fixture : Json) : IO Json := do
  let directory ← IO.ofExcept (fixture.getObjValAs? String "directory")
  let expected ← IO.ofExcept (fixture.getObjValAs? DB.PageMap.Head "head")
  let source ← DB.PageMap.pin (.mk directory)
  check (source.head == expected) "frozen original head changed"
  let seed ← IO.ofExcept (fixture.getObjValAs? (Array Journal.Entry) "seed")
  let analysis ← IO.ofExcept (fixture.getObjValAs? (Array Journal.Entry) "analysis")
  for value in seed++analysis do discard <| Journal.append source value
  let started ← IO.monoMsNow
  let prepared ← Build.refresh source .database
  let preparedMs := (← IO.monoMsNow)-started
  let before ← shared source
  let beforeFacts ← Index.allFacts before.index
  let beforeConsumed := consumed beforeFacts
  let replayStarted ← IO.monoMsNow
  let replayed ← Journal.replay source analysis ((← IO.monoMsNow)+30000)
  let replayMs := (← IO.monoMsNow)-replayStarted
  check (!beforeConsumed.isEmpty && !replayed.consumed.isEmpty) "fixture has no native consumption"
  let equivalent := sameFacts beforeConsumed replayed.consumed
  let _ ← UsageCache.ensure source
  let input : UsageCache.Input := {
    session := "session",turn := "analysis",source := source.head,
    view := Sha256.hex "fixed private projection".toUTF8,count := analysis.size}
  let began ← IO.monoMsNow
  Journal.publish source .database replayed ((← IO.monoMsNow)+30000) input
  let publishMs := (← IO.monoMsNow)-began
  let after ← shared source
  let afterFacts ← Index.allFacts after.index
  -- An incomplete private interpretation must not own public consumption.
  let unfinished := {replayed with consumed := #[],usage := #[],pending := 1}
  Journal.publish source .database unfinished ((← IO.monoMsNow)+30000) input
  let probed ← shared source
  let probeFacts ← Index.allFacts probed.index
  let size ← IO.ofExcept (fixture.getObjValAs? Nat "size")
  let report := Json.mkObj [("size",toJson size),("sourceOnlyPublicMs",toJson preparedMs),
    ("privateReplayMs",toJson replayMs),("privatePublishMs",toJson publishMs),
    ("sourceOnlyMode",toJson prepared.mode),("sourceOnlyConsumed",toJson beforeConsumed),
    ("privateConsumed",toJson replayed.consumed),("sameConsumption",toJson equivalent),
    ("wholeSharedFactsEqual",toJson (sameFacts beforeFacts afterFacts)),
    ("sharedHeadUnchangedByPrivatePublish",toJson (before.index.head == after.index.head)),
    ("privatePartialRemovedPublic",toJson (!sameFacts afterFacts probeFacts)),
    ("privateUsageFacts",toJson replayed.usage.size),("pending",toJson replayed.pending),
    ("unknown",toJson replayed.unknown),("originalHeadUnchanged",toJson ((← DB.PageMap.pin source.directory).head == expected))]
  save (root/s!"size-{size}.json") report
  return report

def run (mode : String) (root : System.FilePath) : IO Unit := do
  if mode == "capture" then
    check (!(← root.pathExists)) "preserve original preparation fixture"
    IO.FS.createDirAll root
    let mut fixtures := #[]
    for size in [0,5000,50000] do fixtures := fixtures.push (← makeFixture (root/toString size) size)
    save (root/"frozen.json") (toJson fixtures)
  else if mode == "observe" then
    let fixtures ← IO.ofExcept (fromJson? (← read (root/"frozen.json")) : Except String (Array Json))
    let resultRoot ← Paths.dataRoot
    let mut rows := #[]
    for fixture in fixtures do rows := rows.push (← observe resultRoot fixture)
    let report := Json.mkObj [("rows",toJson rows),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
    save (resultRoot/"report.json") report
    IO.println report.compress
  else throw (IO.userError "public preparation mode required")

end Eggshell.Research.PublicPreparationChecks
