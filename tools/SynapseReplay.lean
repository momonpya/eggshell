import Eggshell.SynapseArchive

open Lean Eggshell.Synapses Eggshell.Synapses.Extraction

def main (args : List String) : IO Unit := do
  let [beforePath, afterPath, rpc, query, answerPath] := args |
    throw (IO.userError "SynapseReplay BEFORE-EXPORT AFTER-EXPORT RPC QUERY-SHA256 ANSWER")
  unless digest query do throw (IO.userError "expected opaque question digest")
  let before ← Archive.load (.mk beforePath)
  let after ← Archive.load (.mk afterPath)
  let trace ← readTrace (.mk rpc)
  let mut stored := #[]
  let mut original := #[]
  let mut reads : Std.HashMap Occurrence (Array Range) := {}
  let mut issues := #[]
  for (archive, isBefore) in [(before, true), (after, false)] do
    for doc in archive.documents do
      if !doc.native then continue
      match recordedRows archive.database doc with
      | .ok rows =>
        original := original ++ rows
        if isBefore then stored := stored ++ rows.map (·.source)
      | .error reason => issues := issues.push (Json.mkObj [("owner", toJson doc.owner), ("reason", toJson reason)])
  for doc in after.documents do
    if !doc.native then continue
    match locateReads after.database doc trace with
    | .ok located =>
      for value in located do
        let occurrence := value.read.occurrence
        reads := reads.insert occurrence (reads[occurrence]?.getD #[] |>.push value.read.source)
    | .error _ => pure ()
  let mut feedback : Feedback := {}
  let mut finalAnswer : Option (Occurrence × String) := none
  let handle ← IO.FS.Handle.mk (.mk rpc) .read
  while true do
    let line ← handle.getLine
    if line.isEmpty then break
    let record ← IO.ofExcept (Json.parse line)
    if (← IO.ofExcept (record.getObjValAs? String "direction")) != "server" then continue
    let message ← IO.ofExcept (record.getObjVal? "message")
    let method := (message.getObjValAs? String "method").toOption.getD ""
    let params := (message.getObjVal? "params").toOption.getD .null
    if method == "hook/completed" then
      let entries ← IO.ofExcept (params.getObjVal? "run" >>= (·.getObjValAs? (Array Json) "entries"))
      for entry in entries do
        if (← IO.ofExcept (entry.getObjValAs? String "kind")) == "context" then
          let text ← IO.ofExcept (entry.getObjValAs? String "text")
          feedback := feedback.present (presented text (before.documents ++ after.documents) original)
    else if method == "item/started" || method == "item/completed" then
      let item ← IO.ofExcept (params.getObjVal? "item")
      let occurrence : Occurrence := ⟨← IO.ofExcept (params.getObjValAs? String "threadId"),
        ← IO.ofExcept (params.getObjValAs? String "turnId"), ← IO.ofExcept (item.getObjValAs? String "id")⟩
      let kind ← IO.ofExcept (item.getObjValAs? String "type")
      if kind == "agentMessage" && method == "item/completed" then
        finalAnswer := some (occurrence, ← IO.ofExcept (item.getObjValAs? String "text"))
      if kind != "commandExecution" then continue
      if method == "item/started" then feedback := feedback.start occurrence
      else if let some requested := reads[occurrence]? then
        feedback ← IO.ofExcept (feedback.completedRead occurrence query requested stored)
  let answer ← IO.FS.readFile (.mk answerPath)
  let some (occurrence, actual) := finalAnswer |
    throw (IO.userError "no completed answer occurrence in actual RPC")
  unless actual.trimAscii.copy == answer.trimAscii.copy do
    throw (IO.userError "answer file disagrees with completed RPC message")
  feedback ← IO.ofExcept (feedback.answer occurrence query answer)
  let mut counts : Std.HashMap String Nat := {}
  for fact in feedback.graph.snapshot do
    if let .used usage := fact then
      let label := usage.kind.label
      counts := counts.insert label (counts[label]?.getD 0 + 1)
  IO.println (Json.mkObj [("facts", toJson feedback.graph.snapshot),
    ("labels", Json.mkObj (counts.toList.map fun (label, count) => (label, toJson count))),
    ("issues", toJson issues)]).compress
