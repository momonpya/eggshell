import tools.research.RuntimeReadControls
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
namespace Eggshell.Research.TypedReadFixture
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def run : IO Unit := do
  let root := base/"frontend-quiescence-fixture-small1/work.project/owners"
  check (!(← root.pathExists)) "do not overwrite a previous read fixture"
  let mut owners := #[]
  for index in [:2] do
    let owner := root/toString index
    let database := owner/"source.egg"
    let source ← Persistence.ensureSnapshot database
    let session := s!"typed-read-fixture-{index}"
    let domain := Sha256.hex session.toUTF8
    let known ← Journal.knowledge source [] false
    let mut tools := []
    for item in [:4] do
      let body := s!"recorded head source/key-17 警告 owner {index} item {item}\n" ++
        String.join (List.replicate 48 s!"Independent observation {index}/{item}: original output bytes, provenance, scoped owner and recorded range.\n") ++
        "recorded tail source/key-11 探索\n"
      let tool : ToolEvent := {
        name := "synthetic_observation"
        useId := s!"read-{item}"
        input := (Json.mkObj [("owner",toJson index),("item",toJson item)]).compress
        response := (Json.mkObj [("output",toJson body)]).compress }
      let occurrence : Occurrence := ⟨session,"turn",tool.useId⟩
      discard <| Journal.append source ⟨⟨domain,item*2+1⟩,.start occurrence (canonicalToolWork tool)
        (Sha256.hex "typed source read fixture".toUTF8) known,none⟩
      discard <| Journal.append source ⟨⟨domain,item*2+2⟩,.finish occurrence tool.name
        (canonicalJson tool.input) (canonicalJson tool.response) (some source.directory.toString),none⟩
      tools := tools++[tool]
    let pending : PendingTurn := {
      sessionId := session
      turnId := "turn"
      cwd := owner.toString
      prompt := "typed source read fixture"
      profile := "work"
      write := some source.directory.toString
      read := []
      semanticMatcher := none
      handoffChars := 500000
      projection := .none
      tools
      finalMessage := none }
    let request ← NativePublication.prepare pending source.directory true
    let publication ← NativePublication.runPrepared source.directory #[request]
    check (publication.size == 1 && publication.all (·.source.complete)) "synthetic source publication did not ACK"
    let pinned ← DB.PageMap.pin database
    owners := owners.push (Json.mkObj [("owner",toJson index),("database",toJson database.toString),
      ("identity",toJson pinned.head.identity),("observations",toJson (4 : Nat)),("publicationAcked",toJson true)])
  IO.FS.writeFile (base/"typed-fetch-read-fixture.json") (Json.mkObj [("owners",toJson owners),
    ("source",toJson "current Journal and NativePublication; two small DBs, four multi-window original observations each"),
    ("historicalFixtureRestored",toJson false),("originalLlvmDbUnchanged",toJson true)]).compress
end Eggshell.Research.TypedReadFixture
def main := Eggshell.Research.TypedReadFixture.run
