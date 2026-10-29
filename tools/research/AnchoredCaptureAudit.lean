import Eggshell.ContentCapture
import Eggshell.ContentMetadata
import tools.research.AnchoredCaptureContract
open Lean Eggshell ContentCapture ContentCorrespondence

#print axioms Eggshell.ContentRuns.checked_run_original
#print axioms ContentCorrespondence.AnchoredRun.anchor_preserved
#print axioms ContentCapture.Supplement.bound_original
#print axioms ContentCapture.Supplement.producer_is_provenance

private def check (value : Bool) (reason : String) : IO Unit :=
  unless value do throw (IO.userError reason)

private def acquire (root : System.FilePath) (input : Json) (raw : String) : IO (Captured × Nat) := do
  let start ← IO.monoMsNow
  let acquired ← captureInputs root input none (start+10000)
  check (acquired.record.valid && !acquired.record.closed) "fixture did not acquire advisory input"
  let captured ← finish root acquired raw ((← IO.monoMsNow)+10000)
  check (captured.complete && captured.failure.isNone) "fixture did not seal anchored capture"
  check (captured.aliases.all (ContentMetadata.validAlias captured.inputs raw.toList.toArray))
    "anchored alias lost its original projection or input fingerprint"
  return (captured,(← IO.monoMsNow)-start)

private def originalCodes (raw : String) (captured : Captured) : IO (Array (Nat × String)) :=
  captured.aliases.mapM fun alias => do
    let some code := code? raw.toList.toArray alias | throw (IO.userError "literal original changed")
    return (alias.line,code)

private def rejected (action : IO α) : IO Unit := do
  let accepted ← try let _ ← action; pure true catch _ => pure false
  check (!accepted) "foreign or incomplete supplement was accepted"

private def persistence (root : System.FilePath) (database : String) (doc : Synapses.Extraction.Document)
    (parent : Captured) (extra : Supplement) : IO Json := do
  let snapshot ← DB.PageMap.create (root / "prepared-correspondence") "advisory fixture"
  let (_,head,_) ← DB.PageMap.withWriter snapshot fun writer =>
    ContentMetadata.stageSupplement writer database 7 doc parent extra
  let prepared ← DB.PageMap.pin snapshot.directory
  check (prepared.head == head) "supplement publication was not durable"
  let stamp ← ContentMetadata.supplementStamp prepared
  check stamp.isSome "supplement was committed without its preparation stamp"
  let some loaded ← ContentMetadata.loadSupplement? prepared database 7 doc parent |
    throw (IO.userError "supplement disappeared after reopening")
  check ((toJson loaded).compress == (toJson extra).compress)
    "reopened supplement changed provenance or coordinates"
  let (_,retry,_) ← DB.PageMap.withWriter prepared fun writer =>
    ContentMetadata.stageSupplement writer database 7 doc parent extra
  check (retry == head && (← ContentMetadata.supplementStamp (← DB.PageMap.pin snapshot.directory)) == stamp)
    "unchanged preparation republished a supplement"
  rejected (ContentMetadata.loadSupplement? prepared (Sha256.hex "foreign DB".toUTF8) 7 doc parent)
  rejected (ContentMetadata.loadSupplement? prepared database 7 {doc with owner := "v3"} parent)
  rejected (ContentMetadata.loadSupplement? prepared database 7 {doc with work := "v4"} parent)
  rejected (ContentMetadata.loadSupplement? prepared database 7 {doc with source := some "other body"} parent)
  rejected (ContentMetadata.loadSupplement? prepared database 7 doc {parent with aliases := #[]})
  rejected (DB.PageMap.withWriter prepared fun writer =>
    ContentMetadata.stageSupplement writer database 8 doc parent {extra with sealed := false})
  check ((← DB.PageMap.pin snapshot.directory).head == head)
    "rejected supplement changed a committed preparation"
  return Json.mkObj [("durableReopen",toJson true),("idempotentRetry",toJson true),
    ("foreignDatabaseRejected",toJson true),("foreignOwnerRejected",toJson true),
    ("foreignWorkRejected",toJson true),("foreignBodyRejected",toJson true),
    ("changedParentRejected",toJson true),("unsealedRejected",toJson true)]

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "AnchoredCaptureAudit NEW-DIRECTORY")
  let root := System.FilePath.mk destination
  check (root.isAbsolute && !(← root.pathExists)) "new fixture directory required"
  IO.FS.createDir root
  let code := "start_call();\n}\n\n  警告(\"é🧠\");\n}\nend_call();\n"
  IO.FS.writeFile (root / "source.cpp") code
  let mut reports := #[]
  for command in #["cat source.cpp","nl -ba source.cpp",
      "awk '{print FILENAME \":\" NR \":\" $0}' source.cpp"] do
    let observed ← IO.Process.output {cmd := "/bin/sh",args := #["-c",command],cwd := root.toString}
    check (observed.exitCode == 0) "native read fixture failed"
    let (captured,elapsed) ← acquire root (Json.mkObj [("arbitrary_argument",toJson command)]) observed.stdout
    let actual ← originalCodes observed.stdout captured
    IO.println (Json.mkObj [("fixture",toJson command),("codes",toJson actual),
      ("elapsedMs",toJson elapsed)]).compress
    check (actual.contains (2,"}") && actual.contains (5,"}"))
      "anchored repeated source row was lost"
    if command == "cat source.cpp" then
      check (actual.contains (3,"")) "literal empty source row was lost"
    let expected := (code.splitOn "\n").dropLast.toArray
    check (captured.aliases.all fun alias => (expected[alias.line-1]?).isSome)
      "capture invented an input line"
    for (line,text) in actual do
      check (expected[line-1]? == some text) "anchored position differs from original input"
    reports := reports.push (Json.mkObj [("command",toJson command),("elapsedMs",toJson elapsed),
      ("aliases",toJson captured.aliases.size),("repeatedRowsPresent",toJson true),
      ("literalEmptyRowPresent",toJson (actual.contains (3,"")))])
  let input := Json.mkObj [("arguments",toJson #["unrecognized_mcp_reader","source.cpp"])]
  let raw := (Json.mkObj [("arbitrary_mcp_body",toJson ("prefix:" ++ code)),("other",toJson "opaque")]).compress
  let (structured,jsonMs) ← acquire root input raw
  let decoded ← originalCodes raw structured
  check (decoded.contains (2,"}") && decoded.contains (5,"}") && decoded.contains (3,""))
    "JSON/MCP string projection lost anchored original rows"
  let recorded := {structured with
    implementation := Sha256.hex "recorded producer".toUTF8
    aliases := structured.aliases.filter fun alias => alias.line == 1 || alias.line == 4 || alias.line == 6}
  let supplement ← refineSaved root recorded raw ((← IO.monoMsNow)+10000)
  check (supplement.sealed && supplement.boundTo recorded raw &&
      supplement.parentProducer == recorded.implementation && supplement.aliases.size == 3)
    "saved anchors were not refined without replacing their producer"
  let doc : Synapses.Extraction.Document := {
    owner := "v1"
    work := "v2"
    workText := none
    source := some raw
    native := true
    files := #[]
    occurrences := #[⟨"recorded-session","turn","call"⟩]}
  let catalog ← IO.ofExcept (ContentMetadata.catalogSupplement (Sha256.hex "database".toUTF8) doc recorded supplement)
  check (catalog.located.size == 3) "bound supplemental catalog lost additions"
  let borrowed := ContentMetadata.catalogSupplement (Sha256.hex "database".toUTF8)
    {doc with source := some "other"} recorded supplement
  check (!borrowed.isOk) "supplement was borrowed by another original body"
  let persisted ← persistence root (Sha256.hex "database".toUTF8) doc recorded supplement
  let (isolated,_) ← acquire root input "}\n"
  check isolated.aliases.isEmpty "isolated ambiguous row acquired coordinates"
  let broken := "start_call();\n}\n}\n"
  let (prefixCapture,_) ← acquire root input broken
  let partialCodes ← originalCodes broken prefixCapture
  check ((partialCodes.filter (·.2 == "}")).size == 1 && partialCodes.contains (2,"}"))
    "anchored run crossed a mismatching source row"
  IO.FS.writeFile (root / "left.cpp") "left_unique();\n}\nleft_tail();\n"
  IO.FS.writeFile (root / "right.cpp") "right_head();\n}\nright_unique();\n"
  let conflicting := "left_unique();\n}\nright_unique();\n"
  let (mixed,_) ← acquire root (Json.mkObj [("paths",toJson #["left.cpp","right.cpp"])]) conflicting
  check (!((← originalCodes conflicting mixed).any (·.2 == "}")))
    "conflicting file anchors were resolved by iteration order"
  IO.FS.writeFile (root / "subset-a.cpp") "shared_call();\na_unique();\n"
  IO.FS.writeFile (root / "subset-b.cpp") "shared_call();\n"
  let omitted := "shared_call();\nnot_in_inputs();\na_unique();\n"
  let (exported,_) ← acquire root (Json.mkObj [("paths",toJson #["subset-a.cpp","subset-b.cpp"])]) omitted
  check (exported.inputs.size == 1) "fixture did not omit an unmatched input from its public export"
  let restricted ← refineSaved root exported omitted ((← IO.monoMsNow)+10000)
  check (restricted.sealed && restricted.aliases.isEmpty)
    "rescanning exported inputs manufactured new globally unique anchors"
  let acquired ← captureInputs root input none ((← IO.monoMsNow)+10000)
  IO.FS.writeFile (root / "source.cpp") (code.replace "start_call" "changed_call")
  let changed ← finish root acquired code ((← IO.monoMsNow)+10000)
  check (!changed.complete && changed.aliases.isEmpty) "changed input acquired historical coordinates"
  IO.FS.writeFile (root / "source.cpp") code
  let expired ← finish root acquired code (← IO.monoMsNow)
  check (!expired.complete && expired.aliases.isEmpty) "unfinished first scan acquired uniqueness"
  let long := String.ofList (List.replicate (2*1024*1024) 'x') ++ "\n" ++ code
  IO.FS.writeFile (root / "long.cpp") long
  let (bounded,longMs) ← acquire root (Json.mkObj [("path",toJson "long.cpp")]) code
  check ((← originalCodes code bounded).contains (3,"}")) "irrelevant long input row lost later anchored data"
  let repeated := "head_anchor();\n" ++ String.join (List.replicate 10000 "}\n") ++ "tail_anchor();\n"
  IO.FS.writeFile (root / "repeated.cpp") repeated
  let (many,manyMs) ← acquire root (Json.mkObj [("path",toJson "repeated.cpp")]) repeated
  check (many.aliases.size == 10002) "long ambiguous run lost rows"
  let mut budgetReports := #[]
  for (path,body) in #[("source.cpp",code),("long.cpp",code),("repeated.cpp",repeated)] do
    let acquired ← captureInputs root (Json.mkObj [("path",toJson path)]) none ((← IO.monoMsNow)+10000)
    let started ← IO.monoMsNow
    let captured ← finish root acquired body (started+250)
    let elapsed := (← IO.monoMsNow)-started
    check (captured.aliases.all (ContentMetadata.validAlias captured.inputs body.toList.toArray))
      "production-budget capture returned an unchecked projection"
    check (captured.complete || captured.aliases.isEmpty) "unsealed scan leaked partial uniqueness"
    budgetReports := budgetReports.push (Json.mkObj [("path",toJson path),("budgetMs",toJson (250 : Nat)),
      ("elapsedMs",toJson elapsed),("complete",toJson captured.complete),("failure",toJson captured.failure),
      ("aliases",toJson captured.aliases.size)])
  let report := Json.mkObj [("nativeReads",toJson reports),("jsonElapsedMs",toJson jsonMs),
    ("persistence",persisted),("productionCaptureBudget",toJson budgetReports),
    ("longInputElapsedMs",toJson longMs),("longRunElapsedMs",toJson manyMs),("longRunAliases",toJson many.aliases.size),
    ("isolatedAmbiguityRejected",toJson true),("mismatchStopsRun",toJson true),
    ("conflictingAnchorsRejected",toJson true),("changedInputRejected",toJson true),
    ("unfinishedInputRejected",toJson true),("newAuthority",toJson false),
    ("historicalProducerPreserved",toJson true),("supplementBoundToParent",toJson true),
    ("omittedInputDoesNotCreateUniqueness",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("actualHookMeasured",toJson false),("productionAdoption",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
