import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace HistoryProtocolQualification
def document (owner invocation source : String) : Json := Json.mkObj [
  ("owner",toJson owner),("invocation",toJson invocation),("source",toJson source)]
def corpus : Json := Json.mkObj [("head",toJson "protocol-qualification-snapshot"),
  ("documents",toJson #[
    document "build-106" "read recorded image 106" "build = 106\nif (retry_count < 3) return retry;\nLegacy admission flags are ignored in this older image.\n",
    document "build-107" "read recorded image 107" "build = 107\nif (flags & kNoRetry) return denied;\notherwise return retry;\n",
    document "policy-staging" "MCP read mcp://services/celadon/staging" "{\"environment\":\"staging\",\"retention_days\":4,\"drop_when_full\":true}",
    document "policy-production" "MCP read mcp://services/celadon/production" "{\"サービス\":\"青磁\",\"environment\":\"production\",\"etag\":\"b7\",\"retention_days\":21,\"drop_when_full\":false}",
    document "edgelatch-observation" "read captured EdgeLatch admission trace"
      ("EdgeLatch admission observation. A second supporting observation is linked by its stored dependency edge.\n"++
        String.ofList (List.replicate 260 'a')++"\nif (!ready) return busy;\ncontinue_to_lease_check();\n"),
    document "unrelated-admission" "read archived service note" "The Indigo console prints busy while rebuilding its inventory. Its policy is unrelated to EdgeLatch.",
    document "lease-observation" "read captured downstream check"
      ("Downstream lease observation.\n"++String.ofList (List.replicate 280 'b')++
        "\nif (lease_rev != config_rev) return stale;\notherwise accept();\n"),
    document "unrelated-policy" "read another project's policy" "The Ochre project retries all requests and retains its events for 90 days."]),
  ("neighbors",toJson #[Json.mkObj [("document",toJson (4 : Nat)),("edges",toJson #[Json.mkObj [
    ("document",toJson (6 : Nat)),("kind",toJson "supports"),("first",toJson (0 : Nat)),
    ("length",toJson (1000 : Nat))]])]])]
def questions : Json := toJson #[
  Json.mkObj [("name",toJson "image-boundary"),("text",toJson "For the recorded build 107, select the original admission check that disables retry and its otherwise result. Exclude build 106 and other projects."),("expectedText",Json.null)],
  Json.mkObj [("name",toJson "resource-scope"),("text",toJson "青磁サービスのproduction環境について、記録されたetagと保持日数、満杯時に破棄するかを示す元のMCP観測を選んでください。stagingや別プロジェクトは含めないでください。"),("expectedText",Json.null)],
  Json.mkObj [("name",toJson "retained-premises"),("text",toJson "Inspect the recorded EdgeLatch admission observation, follow its stored dependency edge, and select both original checks that distinguish busy from stale, including the accepting alternative. Exclude unrelated service notes."),("expectedText",Json.null)]]
def golden : Json := toJson #[
  Json.mkObj [("name",toJson "image-boundary"),("owners",toJson #["build-107"]),
    ("needles",toJson #["build = 107","if (flags & kNoRetry) return denied;","otherwise return retry;"]),
    ("requiredTools",toJson #["read_history","select_evidence"]),("maxCharacters",toJson (4000 : Nat))],
  Json.mkObj [("name",toJson "resource-scope"),("owners",toJson #["policy-production"]),
    ("needles",toJson #["\"environment\":\"production\"","\"etag\":\"b7\"","\"retention_days\":21","\"drop_when_full\":false"]),
    ("requiredTools",toJson #["read_history","select_evidence"]),("maxCharacters",toJson (4000 : Nat))],
  Json.mkObj [("name",toJson "retained-premises"),("owners",toJson #["edgelatch-observation","lease-observation"]),
    ("needles",toJson #["if (!ready) return busy;","if (lease_rev != config_rev) return stale;","otherwise accept();"]),
    ("requiredTools",toJson #["follow_history","read_history","select_evidence"]),("maxCharacters",toJson (4000 : Nat))]]
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def prepare (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve the frozen independent protocol tasks"
  IO.FS.createDir root
  for (name,value) in [("history",corpus),("questions",questions),("golden",golden)] do
    IO.FS.writeFile (root/(name++".json")) value.compress
  IO.FS.writeFile (root/"policy.json") (Json.mkObj [
    ("arms",toJson #["baseline","candidate"]),("repetitions",toJson (2 : Nat)),
    ("order",toJson #["baseline-1","candidate-1","candidate-2","baseline-2"]),
    ("samePinnedModelAndNativeRuntime",toJson true),("retuneAfterAnyResult",toJson false),
    ("gate",toJson "candidate must pass all three tasks in both fresh repetitions; otherwise no LLVM evaluation"),
    ("formalTokenOrProductAdoption",toJson false)]).compress

def assess (root manifest output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve paired qualification assessment"
  let expected ← IO.ofExcept ((← read (root/"golden.json")).getArr?)
  let runs ← IO.ofExcept ((← read manifest).getArr?)
  check (expected.size == 3 && runs.size == 4) "all predeclared paired runs required"
  let mut reports := #[]
  for run in runs do
    let directory : String ← IO.ofExcept (run.getObjValAs? _ "directory")
    let results ← IO.ofExcept ((← read (System.FilePath.mk directory/"result.json")).getObjValAs? (Array Json) "results")
    check (results.size == expected.size) "paired run has missing task results"
    let mut tasks := #[]
    for index in [:expected.size] do
      let reference := expected[index]!
      let result := results[index]!
      check (reference.getObjValD "name" == result.getObjValD "name") "task identity changed"
      let payload ← IO.ofExcept (result.getObjValAs? (Array Json) "payload")
      let owners : Array String ← IO.ofExcept (reference.getObjValAs? _ "owners")
      let needles : Array String ← IO.ofExcept (reference.getObjValAs? _ "needles")
      let selected ← payload.mapM fun row => IO.ofExcept (row.getObjValAs? String "owner")
      let texts ← payload.mapM fun row => IO.ofExcept (row.getObjValAs? String "text")
      let required : Array String ← IO.ofExcept (reference.getObjValAs? _ "requiredTools")
      let events : Array Json ← IO.ofExcept (result.getObjValAs? _ "events")
      let methods ← events.mapM fun row => IO.ofExcept (row.getObjValAs? String "name")
      let bound : Nat ← IO.ofExcept (reference.getObjValAs? _ "maxCharacters")
      let elapsed : Nat ← IO.ofExcept (result.getObjValAs? _ "elapsedMs")
      let originalComplete := owners.all selected.contains && needles.all fun needle =>
        texts.any fun text => (text.splitOn needle).length > 1
      let noUnrelated := selected.all owners.contains
      let bounded := (texts.map String.length).foldl (·+·) 0 ≤ bound && elapsed < 25000
      let usage : Array Json ← IO.ofExcept (result.getObjValAs? _ "usage")
      let mut tokens := 0
      for cost in usage do
        let input : Nat ← IO.ofExcept (cost.getObjValAs? _ "prompt_tokens")
        let produced : Nat ← IO.ofExcept (cost.getObjValAs? _ "completion_tokens")
        let total : Nat ← IO.ofExcept (cost.getObjValAs? _ "total_tokens")
        check (input+produced == total) "inclusive model usage arithmetic differs"
        tokens := tokens+total
      let files ← (System.FilePath.mk directory/s!"question-{index}").readDir
      let attempts := files.countP fun entry => entry.fileName.startsWith "request-" && entry.fileName.endsWith ".json"
      let passed := result.getObjValD "finished" == toJson true && originalComplete && noUnrelated &&
        required.all methods.contains && bounded
      tasks := tasks.push (Json.mkObj [("name",reference.getObjValD "name"),("passed",toJson passed),
        ("originalComplete",toJson originalComplete),("noUnrelatedOwner",toJson noUnrelated),
        ("requiredToolsUsed",toJson (required.all methods.contains)),("withinLimits",toJson bounded),
        ("elapsedMs",toJson elapsed),("knownInclusiveTokens",toJson tokens),
        ("allGenerationAttemptsAccounted",toJson (attempts == usage.size)),("error",result.getObjValD "error")])
    reports := reports.push (Json.mkObj [("arm",run.getObjValD "arm"),("repetition",run.getObjValD "repetition"),
      ("tasks",toJson tasks),("passed",toJson (tasks.countP (·.getObjValD "passed" == toJson true)))])
  IO.FS.writeFile output (Json.mkObj [("runs",toJson reports),("actualHookDelivery",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end HistoryProtocolQualification
