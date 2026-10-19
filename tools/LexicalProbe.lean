import Eggshell.Install
import tools.RetrievalIndex

open Lean Eggshell RetrievalResearch
open Persistence Store Plugin

private def append (source : Snapshot) (work body : String) : IO Nat := do
  let (id, _, _) ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let edge := OutcomeEdge.make (.text work) (.text body) [] (by simp) (by simp)
    let id ← intern.root edge.relation
    writeChange writer {added := [id], removed := [], unionsChanged := false}
    pure id
  pure id

private def prepare (directory : System.FilePath) : IO Json := do
  IO.FS.createDirAll directory
  let directory ← IO.FS.realPath directory
  let source ← DB.PageMap.create (directory / "source.egg")
    (Persistence.valueToJson (.text "lexical-native-fixture") |>.compress)
  let examples := [
    ("Investigate source one", "한국어 검색 기록 ORIGINAL_KOREAN_BODY"),
    ("Investigate source two", "Поиск сохранённых записей ORIGINAL_CYRILLIC_BODY"),
    ("Investigate source three", "ｶﾞｲﾄﾞ ＡＢＣ１２３ ORIGINAL_WIDTH_BODY"),
    ("Investigate source four", "保存した本文 木材 ORIGINAL_JAPANESE_BODY"),
    ("Investigate source five", "café résumé ORIGINAL_ACCENT_BODY")]
  for (work, body) in examples do
    let _ ← append (← DB.PageMap.pin source.directory) work body
    pure ()
  let snapshot ← DB.PageMap.pin source.directory
  pure (Json.mkObj [("database", toJson source.directory.toString), ("head", toJson snapshot.head),
    ("documents", toJson (← searchDocuments snapshot).length),
    ("legacyKoreanPosting", toJson (← searchPosting snapshot "한국어").1)])

private def saveNative (database : System.FilePath) : IO Json := do
  let session := "lexical-native-writer"
  let files ← sessionFiles session
  let pending : PendingTurn := {
    sessionId := session, turnId := "new-source", cwd := database.parent.getD database |>.toString
    prompt := "Investigate added source", profile := "work", semanticMatcher := none
    read := [database.toString], write := some database.toString
    projection := .automatic, handoffChars := 120000
    finalMessage := some "추가 저장 NEW_LEXICAL_BODY" }
  queueCheckpoint files pending
  let some entry := (← (files.directory / "checkpoints").readDir).toList.head? |
    throw (IO.userError "missing native save checkpoint")
  let some result ← Worker.exchange session "save"
      (Json.mkObj [("session", toJson session), ("path", toJson entry.path.toString)])
      ((← IO.monoMsNow) + 5000) | throw (IO.userError "native save timed out")
  let .ok _ := (fromJson? result : Except String (List String)) |
    throw (IO.userError s!"native save failed: {result.compress}")
  let slot ← Worker.slotFor session "save"
  if let some child ← slot.child.atomically get then Worker.retire slot child
  IO.FS.removeDirAll files.directory
  let snapshot ← DB.PageMap.pin database
  pure (Json.mkObj [("status", toJson "saved"), ("head", toJson snapshot.head),
    ("lexical", ← Index.status snapshot), ("savingChatRemoved", toJson true)])

def main (args : List String) : IO UInt32 := do
  match args with
  | ["codex-worker", role] => Worker.run role
  | "search-provider" :: rest => SearchProvider.run rest
  | ["prepare", directory] => IO.println (← prepare (.mk directory)).compress; pure 0
  | ["save", database] => IO.println (← saveNative (.mk database)).compress; pure 0
  | ["status", database] => IO.println (← Index.status (← DB.PageMap.pin (.mk database))).compress; pure 0
  | _ => throw (IO.userError "lexical probe: prepare DIR | save DB | status DB")
