import Eggshell.Install

open Lean Eggshell Eggshell.Plugin

/-- Read original discovery and focus inputs without changing their publication. -/
def exportInputs (database : System.FilePath) : IO Unit := do
  let snapshot ← DB.PageMap.pin database
  let documents ← Persistence.Store.searchDocuments snapshot
  let reader ← Persistence.Store.NodeReader.new snapshot
  let mut seen : Std.HashSet String := {}
  for document in documents do
    let value ← reader.read document.work
    let some work := Matcher.atomText? value | throw (IO.userError "nontext Work")
    for index in [:document.windows.length] do
      let original ← Persistence.Store.readSearchWindow snapshot document index
      let focus := (original.drop (work.length + 1 - index * 384)).copy
      for text in [original, focus] do
        let key := Persistence.Store.windowKey text
        unless seen.contains key do
          seen := seen.insert key
          IO.println (Json.mkObj [("id", toJson key), ("text", toJson text)]).compress

/-- Uncensored delivery comparison, separate from native hook deadline checks.
The same original question, source workspace, graph and packet budgets are used.
No generation endpoint is involved. -/
def inspectDelivery (database questionFile cache output : System.FilePath)
    (provider : Option System.FilePath := none) : IO Unit := do
  let question ← IO.FS.readFile questionFile
  let binary := provider.getD ((← IO.appPath).withFileName "eggshell")
  let command := [binary.toString, "search-provider", "--cache", cache.toString]
  let started ← IO.monoMsNow
  let selection : Config.Selection := {
    label := "work", read := [⟨"work", database⟩], write := none
    semanticMatcher := some command, handoffChars := 120000
    handoffBytes := some Config.nativeHandoffBytes }
  let context : SourceContext := {
    workspace := (← IO.currentDir), deadline := started + 300000, question }
  let handoff ← automaticHandoff selection question [] false (sourceContext := some context)
  IO.FS.writeFile output (Json.mkObj [
    ("purpose", toJson "uncensored delivery parity diagnosis; not a latency or token result"),
    ("elapsedMs", toJson ((← IO.monoMsNow) - started)), ("handoff", toJson handoff)]).compress

def main (arguments : List String) : IO UInt32 := do
  try
    match arguments with
    | ["inputs", database] => exportInputs (.mk database)
    | ["inspect", database, question, cache, output] =>
        inspectDelivery (.mk database) (.mk question) (.mk cache) (.mk output)
    | ["inspect-provider", database, question, cache, output, provider] =>
        inspectDelivery (.mk database) (.mk question) (.mk cache) (.mk output) (some (.mk provider))
    | _ => throw (IO.userError "delivery_audit inputs DB | inspect DB QUESTION_FILE CACHE OUTPUT")
    return 0
  catch error =>
    IO.eprintln s!"delivery audit: {error}"
    return 1
