import tools.research.StudyLocal
open Lean StudyLocal
namespace RecordGroupsStudy
def root := base/"record-groups"
def parent := base/"canonical-decoder-runtime"
def records := project/"docs/candidates/record-groups"

def setup : IO Unit := do
  idle
  check (!(← root.pathExists)) "preserve current component candidate"
  IO.FS.createDirAll records
  materialize (parent/"build") (root/"source") (root/"build")
    "tools.research.OwnedSelectionRuntime" "record-groups-build-settings.json"
  for module in ["PreparedRecordGroups","RecordGroupsBench"] do
    IO.FS.writeFile (root/"source/tools/research"/(module++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(module++".lean")))
  let entry := root/"source/tools/research/OwnedSelectionRuntime.lean"
  let original ← IO.FS.readFile entry
  let seam := "  | [\"owned-selection-hooks\",input]"
  check ((original.splitOn seam).length == 2) "frozen native entry seam changed"
  let current := "import tools.research.RecordGroupsBench\n"++original.replace seam
    ("  | [\"record-groups-bench\",output] => Eggshell.Research.RecordGroupsBench.run (.mk output); return 0\n"++seam)
  IO.FS.writeFile entry current
  guard "record-groups-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("kind",toJson "native synthetic component; publication-time inverse versus dense query join"),
    ("productSourceChanged",toJson false),("orders",toJson #[#["reference","indexed","dense"],
      #["dense","indexed","reference"],#["indexed","reference","dense"]]),
    ("fullHookOrTokenImprovementMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)])

def prepareRun : IO Unit := do
  idle
  discard <| finished "record-groups-build"
  guard "record-groups-bench" #[(root/"build/StudyMain").toString,"record-groups-bench",(root/"bench").toString]

def prepareAdaptive : IO Unit := do
  idle
  discard <| finished "record-groups-bench"
  let inputs ← ["PreparedRecordGroups","RecordGroupsBench"].toArray.mapM fun name => do
    let witness ← read (root/"build"/("tools_research_"++name++".source"))
    return (name,witness)
  write (records/"component-inputs.json") (toJson inputs)
  for name in ["PreparedRecordGroups","RecordGroupsBench"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let entry := root/"source/tools/research/OwnedSelectionRuntime.lean"
  let original ← IO.FS.readFile entry
  let seam := "Eggshell.Research.RecordGroupsBench.run (.mk output); return 0"
  check ((original.splitOn seam).length == 2) "native benchmark mode changed"
  IO.FS.writeFile entry (original.replace seam "Eggshell.Research.RecordGroupsBench.run (.mk output) true; return 0")
  guard "record-groups-adaptive-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]

def prepareAdaptiveRun : IO Unit := do
  idle
  discard <| finished "record-groups-adaptive-build"
  guard "record-groups-adaptive-bench" #[(root/"build/StudyMain").toString,"record-groups-bench",(root/"adaptive").toString]

def prepareRuntime : IO Unit := do
  idle
  discard <| finished "record-groups-adaptive-bench"
  write (records/"adaptive-component.json") (← read (root/"adaptive/report.json"))
  write (records/"adaptive-resources.json") (← read (base/"record-groups-adaptive-bench.guard.json"))
  let target := root/"runtime"
  materialize (root/"build") (target/"source") (target/"build")
    "tools.research.OwnedSelectionRuntime" "record-groups-runtime-build-settings.json"
  IO.FS.writeFile (target/"source/tools/research/OwnedSelectionRuntime.lean")
    (← IO.FS.readFile (parent/"source/tools/research/OwnedSelectionRuntime.lean"))
  for name in ["PreparedRecordGroups","PreparedOwnerGroups"] do
    IO.FS.writeFile (target/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let one := fun (text before after : String) => do
    check ((text.splitOn before).length == 2) "record group product seam changed"
    pure (text.replace before after)
  let metadata := target/"source/tools/research/PreparedSourceView.lean"
  let source ← IO.FS.readFile metadata
  let source ← one source "public import tools.research.MemoGroupFold\n"
    "public import tools.research.MemoGroupFold\npublic import tools.research.PreparedRecordGroups\n"
  let source ← one source "  focus : Option PreparedFocusFacts.Ready := none\n"
    "  focus : Option PreparedFocusFacts.Ready := none\n  groups : Eggshell.Research.PreparedRecordGroups.Index stored.records\n"
  let source ← one source "  return ⟨stored,rows,units,json,bytes,focus⟩"
    ("  let groups := Eggshell.Research.PreparedRecordGroups.prepare stored.records\n"++
     "  -- Existing image accounting reserves 32 bytes per counted byte.\n"++
     "  -- Charge an additional 64 bytes per record and twice per incidence.\n"++
     "  let bytes := bytes+2*(stored.records.length+2*(stored.records.foldl (fun n record => n+record.length) 0))\n"++
     "  return ⟨stored,rows,units,json,bytes,focus,groups⟩")
  let source ← one source
    "  let selected := hashDistinct (requested ++ (ready.stored.records.filter fun record =>\n    record.any requested.contains).flatten)"
    "  let selected := ready.groups.expand requested"
  IO.FS.writeFile metadata source
  let service := target/"source/Eggshell/PublicationService.lean"
  IO.FS.writeFile service (← one (← IO.FS.readFile service) "public import Eggshell.Handoff\n"
    "public import Eggshell.Handoff\npublic import tools.research.PreparedOwnerGroups\n")
  guard "record-groups-runtime-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-runtime-build-settings.json").toString]
  write (records/"runtime-plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("target",toJson target.toString),("newMutableCacheOrLock",toJson false),
    ("indexBuiltInDecodeOwner",toJson true),("indexBuiltInGroupQuery",toJson false),
    ("storedFormatChanged",toJson false),("preparedIndexChargeBytesPerRecordAndTwicePerIncidence",toJson (64 : Nat)),
    ("actualHookImprovementMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def preparePreflight : IO Unit := do
  idle
  discard <| finished "record-groups-runtime-build"
  let target := root/"runtime"
  let auditor := #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]
  discard <| command "/usr/bin/env" (auditor++#["inspect",(target/"build").toString,(records/"runtime-native.json").toString])
  discard <| command "/usr/bin/env" (auditor++#["compare-sources",(parent/"build").toString,
    (target/"build").toString,(records/"runtime-sources.json").toString,
    "tools.research.PreparedSourceView","Eggshell.PublicationService",
    "+tools.research.PreparedRecordGroups","+tools.research.PreparedOwnerGroups"])
  IO.FS.createDirAll (target/"prefix/libexec")
  discard <| command "/bin/ln" #["-s",(target/"build/StudyMain").toString,(target/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/ln" #["-s",(parent/"prefix/share").toString,(target/"prefix/share").toString]
  let output := target/"preflight"
  let runtime := target/"prefix/libexec/eggshell"
  let config := output/"config.toml"
  let reference ← read (parent/"preflight-input.json")
  let environments : Array (String × Option String) ← IO.ofExcept (fromJson? (reference.getObjValD "environment"))
  let environments := environments.map fun (key,value) => (key,
    if key == "EGGSHELL_PREFIX" then some (target/"prefix").toString
    else if key == "PLUGIN_ROOT" then some (target/"prefix/share/eggshell/codex-plugin").toString
    else if key == "EGGSHELL_CONFIG" then some config.toString else value)
  let input := Json.mkObj ((← IO.ofExcept reference.getObj?).toArray.toList.filter (fun row =>
    !["output","runtime","runtimeSha256","plugin","config","environment","counts","diagnostic"].contains row.1)++[
    ("output",toJson output.toString),("runtime",toJson runtime.toString),
    ("runtimeSha256",toJson (← hash runtime)),("plugin",toJson (target/"prefix/share/eggshell/codex-plugin").toString),
    ("config",toJson config.toString),("environment",toJson environments),
    ("counts",toJson (#[(4 : Nat)])),("diagnostic",toJson true)])
  let path := target/"preflight-input.json"
  check (!(← path.pathExists) && !(← output.pathExists)) "preserve hook preflight"
  write path input
  let unsets := environments.foldl (fun args (key,value) =>
    if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environments.filterMap fun (key,value) => value.map (key++"="++·)
  guard "record-groups-preflight" (#["/usr/bin/env"]++unsets++assignments++
    #[runtime.toString,"owned-selection-capacity",path.toString])

def prepareTrial (label : String) (origin : System.FilePath) : IO Unit := do
  let output := root/"runtime"/label
  let runtime := origin/"prefix/libexec/eggshell"
  let config := output/"config.toml"
  let reference ← read (parent/"preflight-input.json")
  let environments : Array (String × Option String) ← IO.ofExcept (fromJson? (reference.getObjValD "environment"))
  let environments := environments.map fun (key,value) => (key,
    if key == "EGGSHELL_PREFIX" then some (origin/"prefix").toString
    else if key == "PLUGIN_ROOT" then some (origin/"prefix/share/eggshell/codex-plugin").toString
    else if key == "EGGSHELL_CONFIG" then some config.toString else value)
  let input := Json.mkObj ((← IO.ofExcept reference.getObj?).toArray.toList.filter (fun row =>
    !["output","runtime","runtimeSha256","plugin","config","environment","counts","diagnostic"].contains row.1)++[
    ("output",toJson output.toString),("runtime",toJson runtime.toString),
    ("runtimeSha256",toJson (← hash runtime)),("plugin",toJson (origin/"prefix/share/eggshell/codex-plugin").toString),
    ("config",toJson config.toString),("environment",toJson environments),
    ("counts",toJson (#[(4 : Nat),16])),("diagnostic",toJson false)])
  let path := root/"runtime"/(label++"-input.json")
  check (!(← path.pathExists) && !(← output.pathExists)) "preserve comparison arm"
  write path input
  let unsets := environments.foldl (fun args (key,value) => if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environments.filterMap fun (key,value) => value.map (key++"="++·)
  guard ("record-groups-"++label) (#["/usr/bin/env"]++unsets++assignments++
    #[runtime.toString,"owned-selection-capacity",path.toString])

def prepareComparison : IO Unit := do
  idle
  discard <| finished "record-groups-preflight"
  check ((← read (root/"runtime/preflight/phase-4/result.json")).getObjValD "passed" == toJson true)
    "complete semantic/synapse/body/ACK preflight required"
  for (label,origin) in [("a-first",parent),("b-first",root/"runtime"),("b-second",root/"runtime"),("a-second",parent)] do
    prepareTrial label origin
  write (records/"comparison-plan.json") (Json.mkObj [("order",toJson #["a-first","b-first","b-second","a-second"]),
    ("countsPerArm",toJson (#[(4 : Nat),16])),("maximumClientsOnThisMac",toJson (16 : Nat)),
    ("sameOriginalSnapshotAndAuditedBodies",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def collect : IO Unit := do
  idle
  let destination := records/"comparison.json"
  check (!(← destination.pathExists)) "preserve complete trial evidence"
  let mut arms := #[]
  let mut verified := 0
  for label in ["preflight","a-first","b-first","b-second","a-second"] do
    let monitor ← finished ("record-groups-"++label)
    let directory := root/"runtime"/label
    let input ← read (root/"runtime"/(label++"-input.json"))
    let topics ← IO.ofExcept ((input.getObjValD "topics").getArr?)
    let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
    let verify := fun (rows : Array Json) (clientRoot : System.FilePath) => do
      let mut published := #[]
      for row in rows do
        let client ← IO.ofExcept (row.getObjValAs? Nat "client")
        let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
        let some spec := topics.find? (fun value => value.getObjValD "topic" == toJson topic) |
          throw (IO.userError "unknown frozen topic")
        let stdout := clientRoot/s!"client-{client}/stdout"
        let value ← read stdout
        let body : System.FilePath := .mk (← IO.ofExcept (spec.getObjValAs? String "body"))
        check ((value.getObjValD "hookSpecificOutput").getObjValD "additionalContext" ==
          toJson (← IO.FS.readFile body)) "published stdout changed the original evidence body"
        let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
        let received := data/"receipts"/receipt
        let actual := (← read (received/"published.json")).getObjValD "data"
        check (actual.getObjValD "sha256" == toJson (← hash stdout)) "publication receipt differs from actual stdout"
        let trace := ((← read (received/"search.json")).getObjValD "data").getObjValD "trace"
        let synapses := (← read (received/"synaptic-delivery.json")).getObjValD "data"
        check (trace.getObjValD "semantic" == toJson "completed" && trace.getObjValD "route" == toJson "configured" &&
          synapses.getObjValD "complete" == toJson true && synapses.getObjValD "packetVerified" == toJson true &&
          row.getObjValD "acknowledged" == toJson true && row.getObjValD "success" == toJson true)
          "semantic/synapse/ACK evidence is incomplete"
        published := published.push (Json.mkObj [("client",toJson client),("topic",toJson topic),
          ("elapsedMs",row.getObjValD "elapsedMs"),("stdoutSha256",actual.getObjValD "sha256"),
          ("bodySha256",spec.getObjValD "sha256"),("receipt",toJson receipt)])
      return published
    let primes ← verify (← IO.ofExcept (fromJson? (← read (directory/"prime.json")))) (directory/"prime")
    verified := verified+primes.size
    let mut phases := #[]
    for count in (if label == "preflight" then [4] else [4,16]) do
      let result ← read (directory/s!"phase-{count}/result.json")
      check (result.getObjValD "passed" == toJson true) "planned capacity phase failed"
      let published ← verify (← IO.ofExcept (fromJson? (result.getObjValD "rows"))) (directory/s!"phase-{count}")
      verified := verified+published.size
      phases := phases.push (Json.mkObj [("clients",toJson count),("wallMs",result.getObjValD "wallMs"),
        ("published",toJson published)])
    let report ← read (directory/"report.json")
    check (report.getObjValD "originalSourceFilesUnchanged" == toJson true) "frozen original DB changed"
    let counters ← read (directory/(if label == "preflight" then "cache-stats-phase-4.json" else "cache-stats-phase-16.json"))
    arms := arms.push (Json.mkObj [("label",toJson label),("runtimeSha256",input.getObjValD "runtimeSha256"),
      ("guard",monitor),("primes",toJson primes),("phases",toJson phases),("palettes",counters.getObjValD "paletteQueries")])
  write destination (Json.mkObj [("verifiedPublishedClients",toJson verified),("allBodiesSemanticSynapsesAndAck",toJson true),
    ("sameFrozenOriginalSource",toJson true),("arms",toJson arms),("answeringModelCalls",toJson (0 : Nat)),
    ("paidMatchedComparisons",toJson (0 : Nat)),("adopted",toJson false)])

def checkInputs : IO Unit := do
  idle
  let runtime := root/"runtime"
  let mut witnesses : Array (String × String) := #[]
  for name in ["tools.research.PreparedSourceView","Eggshell.PublicationService","tools.research.OwnedSelectionRuntime",
      "tools.research.PreparedRecordGroups","tools.research.PreparedOwnerGroups"] do
    let (sealed,_) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read (runtime/"build"/(name.replace "." "_"++".source"))))
    let source := runtime/"source"/(name.replace "." "/"++".lean")
    check (sealed == (← IO.FS.readFile source)) "compiled source differs from the prepared candidate"
    if name == "tools.research.OwnedSelectionRuntime" then
      let (original,_) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (parent/"build"/(name.replace "." "_"++".source"))))
      check (sealed == original) "native comparison entry changed"
    if ["tools.research.PreparedRecordGroups","tools.research.PreparedOwnerGroups"].contains name then
      check (sealed == (← IO.FS.readFile (project/(name.replace "." "/"++".lean")))) "proved helper differs from the native helper"
    witnesses := witnesses.push (name,← hash source)
  write (records/"runtime-inputs.json") (Json.mkObj [("sourceSha256",toJson witnesses),
    ("entryBytesUnchanged",toJson true),("compiledHelpersMatchProvedSources",toJson true),
    ("compiledSourcesMatchPreparedCandidate",toJson true)])

def prepareBorrowed : IO Unit := do
  idle
  check ((← read (records/"comparison.json")).getObjValD "verifiedPublishedClients" == toJson (99 : Nat))
    "close the fixed hook comparison before changing its primitive"
  IO.FS.writeFile (root/"source/tools/research/PreparedRecordGroups.lean")
    (← IO.FS.readFile (project/"tools/research/PreparedRecordGroups.lean"))
  guard "record-groups-borrowed-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]

def prepareBorrowedRun : IO Unit := do
  idle
  discard <| finished "record-groups-borrowed-build"
  guard "record-groups-borrowed-bench" #[(root/"build/StudyMain").toString,"record-groups-bench",(root/"borrowed").toString]

def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => setup
  | ["prepare-run"] => prepareRun
  | ["prepare-adaptive"] => prepareAdaptive
  | ["prepare-adaptive-run"] => prepareAdaptiveRun
  | ["prepare-runtime"] => prepareRuntime
  | ["prepare-preflight"] => preparePreflight
  | ["prepare-comparison"] => prepareComparison
  | ["collect"] => collect
  | ["check-inputs"] => checkInputs
  | ["prepare-borrowed"] => prepareBorrowed
  | ["prepare-borrowed-run"] => prepareBorrowedRun
  | _ => throw (IO.userError "setup|prepare-run required")
end RecordGroupsStudy
def main := RecordGroupsStudy.main
