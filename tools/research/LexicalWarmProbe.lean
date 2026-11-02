import tools.RetrievalIndex
open Lean Eggshell

def main (args : List String) : IO Unit := do
  if let ["query",directory,unit,output] := args then
    unless !(← (System.FilePath.mk output).pathExists) do throw (IO.userError "preserve probe result")
    let source ← DB.PageMap.pin (.mk directory)
    let some reader ← RetrievalResearch.Index.open? source | throw (IO.userError "probe reader unavailable")
    let (owners,count) ← reader.posting unit
    IO.FS.writeFile (.mk output) (Json.mkObj [("owners",toJson owners),("count",toJson count)]).pretty
    return
  let [directory,output] := args | throw (IO.userError "LexicalWarmProbe SOURCE OUTPUT")
  unless !(← (System.FilePath.mk output).pathExists) do throw (IO.userError "preserve probe result")
  let source ← DB.PageMap.pin (.mk directory)
  source.trace.set (some {})
  let started ← IO.monoMsNow
  let result ← RetrievalResearch.Index.warm source .user
  let elapsedMs := (← IO.monoMsNow)-started
  let trace ← source.trace.get
  let sourceRanges := trace.map (fun value => value.operations.foldl (fun count item =>
    count + match item with | .range .. => 1 | _ => 0) 0)
  unless (← RetrievalResearch.Index.ready source) &&
      (← DB.PageMap.pin source.directory).head == source.head do
    throw (IO.userError "probe did not prepare its exact immutable source")
  let report := Json.mkObj [("source",toJson source.head),("result",toJson result),
    ("elapsedMs",toJson elapsedMs),("sourceTraceComplete",toJson (trace.any (·.complete))),
    ("sourceRangeReads",toJson sourceRanges),("sourceReads",toJson (← source.reads.get)),
    ("sourceReadBytes",toJson (← source.readBytes.get)),("modelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (.mk output) report.pretty
  IO.println report.compress
