import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace HistoryToolQualification
def record (owner operation text : String) : Json := Json.mkObj [
  ("owner",toJson owner),("invocation",toJson operation),("source",toJson text)]
def edge (target : Nat) : Json := Json.mkObj [("document",toJson target),
  ("kind",toJson "supports"),("first",toJson (0 : Nat)),("length",toJson (1000 : Nat))]
def documents : Array Json := #[
  record "noise-a" "read uptime" "Telemetry is sampled every fifteen seconds.",
  record "noise-b" "list documentation" "The Marigold editor theme is blue.",
  record "noise-c" "read archived note" "The retired service Harbor retained events for 90 days.",
  record "kestrel-decision" "read incident decision" "Kestrel retry is suppressed by the resource guard. Its recorded supporting observation is linked by a dependency edge; inspect that original before selecting the evidence.",
  record "noise-d" "read packaging note" "Orchid packaging uses a violet icon. This is not an authorization rule.",
  record "noise-e" "read scheduling note" "A meeting about lighthouse renovation is on Friday.",
  record "lighthouse-json" "MCP read resource mcp://support/lighthouse/policy" "{\"service\":\"灯台\",\"policy\":{\"mode\":\"drain\",\"retention_days\":14,\"drop_when_full\":false}}",
  record "noise-f" "read finance note" "The budget for the Garden project is unchanged.",
  record "orchid-observation" "read complete authorization observation"
    ("Orchid authorization observation. The actual guard and result are recorded after the padding below; continue reading until the end.\n"++
      String.ofList (List.replicate 4900 'z')++"\nif (kind == queued && token.valid()) grant();\nelse return denied;\n"),
  record "kestrel-condition" "read observed resource guard"
    "Kestrel resource guard, exact observed text:\nif (used >= quota || retry_count == 0) return suppressed;\notherwise allow_retry();\n",
  record "noise-g" "read inventory" "Twelve spare network adapters are in storage.",
  record "noise-h" "read unrelated rule" "Dahlia permits retries when its timeout expires."]
def fixture : Json := Json.mkObj [("head",toJson "read-tool-qualification-fixed-snapshot"),
  ("documents",toJson documents),("neighbors",toJson #[Json.mkObj [
    ("document",toJson (3 : Nat)),("edges",toJson #[edge 9])]])]
def questions : Array Json := #[
  Json.mkObj [("name",toJson "dependency"),("text",toJson "For Kestrel retry suppression, select both the saved decision and its original supporting guard. Search the recorded history and follow the decision's dependency edge. Exclude unrelated records."),("expectedText",Json.null)],
  Json.mkObj [("name",toJson "japanese-json"),("text",toJson "灯台サービスのdrainモードに関する保存済みポリシーを調べ、保持日数と満杯時の扱いが分かる元のJSONを根拠として選んでください。別サービスの記録は含めないでください。"),("expectedText",Json.null)],
  Json.mkObj [("name",toJson "continued-original"),("text",toJson "Inspect the complete recorded Orchid authorization observation. Select only the original guard and its denied result, found near the end of the observation. Continue reading if the original is paginated; exclude the packaging note and padding."),("expectedText",Json.null)]]
def golden : Json := toJson #[
  Json.mkObj [("name",toJson "dependency"),("owners",toJson #["kestrel-decision","kestrel-condition"]),
    ("needles",toJson #["retry is suppressed by the resource guard","if (used >= quota || retry_count == 0) return suppressed;"]),
    ("requiredTools",toJson #["search_history","follow_history","read_history","select_evidence"]),("maxCharacters",toJson (4000 : Nat))],
  Json.mkObj [("name",toJson "japanese-json"),("owners",toJson #["lighthouse-json"]),
    ("needles",toJson #["\"mode\":\"drain\"","\"retention_days\":14","\"drop_when_full\":false"]),
    ("requiredTools",toJson #["search_history","read_history","select_evidence"]),("maxCharacters",toJson (4000 : Nat))],
  Json.mkObj [("name",toJson "continued-original"),("owners",toJson #["orchid-observation"]),
    ("needles",toJson #["if (kind == queued && token.valid()) grant();","else return denied;"]),
    ("requiredTools",toJson #["read_history","select_evidence"]),("maxCharacters",toJson (800 : Nat))]]
def read (path : String) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def prepare (root : String) : IO Unit := do
  let output := System.FilePath.mk root
  check (!(← output.pathExists)) "fresh frozen qualification inputs required"
  IO.FS.createDir output
  IO.FS.writeFile (output/"history.json") fixture.compress
  IO.FS.writeFile (output/"questions.json") (toJson questions).compress
  IO.FS.writeFile (output/"golden.json") golden.compress
  IO.FS.writeFile (output/"policy.json") (Json.mkObj [
    ("gate",toJson "all three tasks must finish, cover every required original, exclude other owners and obey the fixed wire/deadline limits; only then repeat all three in fresh contexts"),
    ("maxRepetitions",toJson (2 : Nat)),("modelTuningOrLLVMQueriesAllowed",toJson false),
    ("adoptionClaim",toJson false)]).compress
def assess (responsePath goldenPath output : String) : IO Unit := do
  check (!(← (System.FilePath.mk output).pathExists)) "preserve the qualification assessment"
  let results ← IO.ofExcept ((← read responsePath).getObjValAs? (Array Json) "results")
  let expected ← IO.ofExcept ((← read goldenPath).getArr?)
  check (results.size == expected.size && results.size == 3) "all frozen tool tasks required"
  let mut reports := #[]
  for index in [:results.size] do
    let result := results[index]!
    let expected := expected[index]!
    check (result.getObjValD "name" == expected.getObjValD "name") "task identity differs"
    let payload ← IO.ofExcept (result.getObjValAs? (Array Json) "payload")
    let owners ← IO.ofExcept (expected.getObjValAs? (Array String) "owners")
    let selected ← payload.mapM (fun item => IO.ofExcept (item.getObjValAs? String "owner"))
    let texts ← payload.mapM (fun item => IO.ofExcept (item.getObjValAs? String "text"))
    let needles ← IO.ofExcept (expected.getObjValAs? (Array String) "needles")
    let methods ← IO.ofExcept ((← IO.ofExcept (result.getObjValAs? (Array Json) "events")).mapM
      (fun item => item.getObjValAs? String "name"))
    let required ← IO.ofExcept (expected.getObjValAs? (Array String) "requiredTools")
    let bound ← IO.ofExcept (expected.getObjValAs? Nat "maxCharacters")
    let elapsed ← IO.ofExcept (result.getObjValAs? Nat "elapsedMs")
    let originalComplete := owners.all selected.contains && needles.all (fun needle => texts.any (fun text => (text.splitOn needle).length > 1))
    let noUnrelated := selected.all owners.contains
    let toolsUsed := required.all methods.contains
    let bounded := (texts.map String.length).foldl (·+·) 0 ≤ bound && elapsed < 25000
    let passed := result.getObjValD "finished" == toJson true && originalComplete && noUnrelated && toolsUsed && bounded
    reports := reports.push (Json.mkObj [("name",expected.getObjValD "name"),("passed",toJson passed),
      ("originalComplete",toJson originalComplete),("noUnrelatedOwner",toJson noUnrelated),("requiredToolsUsed",toJson toolsUsed),
      ("withinLimits",toJson bounded),("elapsedMs",toJson elapsed),("error",result.getObjValD "error")])
  IO.FS.writeFile output (Json.mkObj [("tasks",toJson reports),
    ("allPassed",toJson (reports.all (·.getObjValD "passed" == toJson true))),("adopted",toJson false)]).compress
end HistoryToolQualification
def main : List String → IO Unit
  | ["prepare",root] => HistoryToolQualification.prepare root
  | ["assess",response,golden,output] => HistoryToolQualification.assess response golden output
  | _ => throw (IO.userError "HistoryToolQualification prepare|assess")
