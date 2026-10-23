import tools.research.StudyCommand
import Eggshell.Install

open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def corpus (database output : String) : IO Unit := do
  check (!(← (System.FilePath.mk output).pathExists)) "keep the frozen numerical corpus"
  let source ← DB.PageMap.pin (.mk database)
  let mut seen : Std.HashSet String := {}
  let mut texts := #[]
  for document in ← Persistence.Store.searchDocuments source do
    for index in [:document.windows.length] do
      let key := document.windows[index]!
      if seen.contains key then continue
      seen := seen.insert key
      texts := texts.push (← Persistence.Store.readSearchWindow source document index)
  for (sample, count) in #[
      ("カーネルのスケジューラを調べ、依存関係と境界の条件を確認する。", 40),
      ("커널 스케줄러의 의존 관계와 경계 조건을 분석합니다. ", 40),
      ("café naïve école программист анализирует зависимости ", 40),
      ("template<class T> auto f(T x) { return x.template get<T>(); }\n", 40)] do
    texts := texts.push (String.join (List.replicate count sample))
  check (texts.size > 32) "numerical corpus must exercise complete segment batches"
  let mut requests := #[]
  let mut offset := 0
  while offset < texts.size do
    let batch := texts.extract offset (offset+32)
    requests := requests.push (Json.mkObj [("texts",toJson batch)])
    offset := offset+32
  IO.FS.writeFile (.mk output) (("\n".intercalate (requests.toList.map Json.compress)) ++ "\n")
  IO.println ((Json.mkObj [("windowsAndSamples",toJson texts.size),("requests",toJson requests.size),
    ("source",toJson database),("sourceHead",toJson source.head),
    ("requestsSha256",toJson (Sha256.hex (← IO.FS.readBinFile (.mk output))))]).compress)

private def probe (python script models requests output : String) : IO Unit := do
  let root := System.FilePath.mk output
  check (root.isAbsolute && !(← root.pathExists)) "new absolute numerical probe directory required"
  IO.FS.createDir root
  let quote := Install.shellQuote
  let lease := root / "encoder.guard"
  let command := "exec " ++ quote python ++ " " ++ quote script ++ " " ++ quote MiniLM.model ++ " " ++
    quote models ++ " 4 " ++ quote lease.toString ++ " index < " ++ quote requests
  let result ← StudyCommand.run "/bin/sh" #["-c",command]
    #[("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
      ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1")]
    root.toString "" (root / "numerical") 180000
  check (result.exitCode == 0) s!"numerical probe failed: {result.stderr}"
  let replies := (result.stdout.splitOn "\n").filter (!·.isEmpty)
  let inputs := ((← IO.FS.readFile (.mk requests)).splitOn "\n").filter (!·.isEmpty)
  check (replies.length == inputs.length) "numerical reply count differs from the frozen corpus"
  let mut numerical := #[]
  let mut vectorCount := 0
  for (input,reply) in inputs.zip replies do
    let response ← IO.ofExcept (Json.parse reply)
    if let .ok error := response.getObjValAs? String "error" then throw (IO.userError error)
    let texts ← IO.ofExcept (Json.parse input >>= (·.getObjValAs? (Array String) "texts"))
    let groups ← IO.ofExcept (response.getObjValAs? (Array (Array (Array Float))) "vectors")
    check (groups.size == texts.size && groups.all (fun group => !group.isEmpty &&
      group.all (fun vector => vector.size == 384 && vector.all Float.isFinite))) "invalid MiniLM vector groups"
    vectorCount := vectorCount + groups.foldl (fun count group => count+group.size) 0
    numerical := numerical.push (Json.mkObj [
      ("vectors",← IO.ofExcept (response.getObjVal? "vectors")),
      ("coverage",← IO.ofExcept (response.getObjVal? "coverage"))])
  IO.FS.writeFile (root / "values.json") ((toJson numerical).compress ++ "\n")
  IO.FS.writeFile (root / "result.json") ((Json.mkObj [
    ("scriptSha256",toJson (Sha256.hex (← IO.FS.readBinFile (.mk script)))),
    ("requestsSha256",toJson (Sha256.hex (← IO.FS.readBinFile (.mk requests)))),
    ("valuesSha256",toJson (Sha256.hex (← IO.FS.readBinFile (root / "values.json")))),
    ("requests",toJson inputs.length),("vectors",toJson vectorCount),
    ("checkedScalars",toJson (vectorCount*384)),("answeringModelCalls",toJson (0 : Nat))]).compress ++ "\n")

def main (args : List String) : IO Unit := do
  match args with
  | ["corpus",database,output] => corpus database output
  | ["probe",python,script,models,requests,output] => probe python script models requests output
  | ["compare",original,candidate,output] =>
      check (!(← (System.FilePath.mk output).pathExists)) "keep the numerical comparison"
      let before ← IO.FS.readBinFile (.mk original)
      let after ← IO.FS.readBinFile (.mk candidate)
      let same := before == after
      IO.FS.writeFile (.mk output) ((Json.mkObj [
        ("vectorsAndCoverageByteIdentical",toJson same),("bytes",toJson before.size),
        ("originalSha256",toJson (Sha256.hex before)),("candidateSha256",toJson (Sha256.hex after)),
        ("answeringModelCalls",toJson (0 : Nat))]).compress ++ "\n")
      check same "allocator change altered numerical vectors or token coverage"
  | _ => throw (IO.userError "ArenaChecks corpus DB JSONL | probe PYTHON SCRIPT MODELS REQUESTS OUTPUT | compare ORIGINAL CANDIDATE REPORT")
