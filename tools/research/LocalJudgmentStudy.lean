import tools.research.StudyLocal
open Lean StudyLocal
namespace LocalJudgmentStudy
def root := base/"practical-runtime/local-judgment"
def records := project/"docs/candidates/local-judgment/native-probe"
def schedule (tag : String) : IO Unit :=
  guard tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/LocalJudgmentStudy.lean").toString,"download"]
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "preserve prior local judge probe"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let assets := Json.mkObj [
    ("runtime",Json.mkObj [
      ("url",toJson "https://github.com/ggml-org/llama.cpp/releases/download/b12110/llama-b12110-bin-macos-arm64.tar.gz"),
      ("sha256",toJson "4f5b8de12e0b9516658ca6a5764c6ffb3d7c659c3dd538556b1413c7b4050662"),
      ("bytes",toJson (16650691 : Nat))]),
    ("model",Json.mkObj [
      ("url",toJson "https://huggingface.co/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/resolve/a02f48bb4f057028298c21fa033da2b30d7742d5/qwen3-reranker-0.6b-q8_0.gguf"),
      ("sha256",toJson "22c9979ce4fbcdc5acdc310c6641c32797eff1aa980b8f7a2db8a8ea23429a48"),
      ("bytes",toJson (639153184 : Nat))]),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))]
  write (records/"assets.json") assets
  schedule "local-judgment-native-assets"
def download : IO Unit := do
  let assets ← read (records/"assets.json")
  for (key,name) in [("runtime","runtime.tar.gz"),("model","model.gguf")] do
    let descriptor := assets.getObjValD key
    let url ← IO.ofExcept (descriptor.getObjValAs? String "url")
    let expected ← IO.ofExcept (descriptor.getObjValAs? String "sha256")
    let size ← IO.ofExcept (descriptor.getObjValAs? Nat "bytes")
    let path := root/name
    check (!(← path.pathExists)) "fresh model download required"
    discard <| command "/usr/bin/curl" #["-fL","--silent","--show-error","--max-time","300",
      "--max-filesize",toString size,"--output",path.toString,url]
    check ((← path.metadata).byteSize.toNat == size && (← hash path) == expected)
      "downloaded native model or engine differs from the pinned artifact"
  let entries := (← command "/usr/bin/tar" #["-tzf",(root/"runtime.tar.gz").toString]).splitOn "\n"
  check (entries.all fun name => !name.startsWith "/" && !(name.splitOn "/").contains "..")
    "runtime archive escapes its isolated directory"
  IO.FS.createDirAll (root/"runtime")
  discard <| command "/usr/bin/tar" #["-xzf",(root/"runtime.tar.gz").toString,"-C",(root/"runtime").toString]
  IO.FS.removeFile (root/"runtime.tar.gz")
  write (records/"downloaded.json") (assets.setObjVal! "archiveRemovedAfterExtraction" (toJson true))
def prepareProbe : IO Unit := do
  idle
  discard <| finished "local-judgment-native-assets"
  let parent := base/"practical-runtime/source-snapshot"
  check (!(← (root/"source").pathExists) && !(← (root/"probe-build").pathExists))
    "preserve the previous numerical probe build"
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  IO.FS.writeFile (root/"source/tools/research/LocalJudgmentProbe.lean")
    (← IO.FS.readFile (project/"tools/research/LocalJudgmentProbe.lean"))
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"probe-build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.LocalJudgmentProbe")
  write (root/"probe-settings.json") settings
  guard "local-judgment-probe-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"probe-settings.json").toString]
def runProbe (tag : String := "local-judgment-probe-build") : IO Unit := do
  idle
  write (records/"build.guard.json") (← finished tag)
  let engine := root/"runtime/llama-b12110"
  let model := root/"model.gguf"
  check ((← hash model) == "22c9979ce4fbcdc5acdc310c6641c32797eff1aa980b8f7a2db8a8ea23429a48")
    "downloaded judge model changed"
  let mut runtimeFiles := #[]
  for entry in ← engine.readDir do
    if entry.fileName.endsWith ".dylib" && (← entry.path.symlinkMetadata).type == .file then
      runtimeFiles := runtimeFiles.push (Json.mkObj [("path",toJson entry.path.toString),
        ("sha256",toJson (← hash entry.path))])
  let request := fun (documents : Array String) => Json.mkObj [
    ("query",toJson "日本の首都はどこですか？"),("documents",toJson documents),("top_n",toJson (2 : Nat))]
  let relevant := "日本の首都は東京です。"
  let unrelated := "重力は質量を持つ物体同士に働く力です。"
  let plan := Json.mkObj [("executable",Json.mkObj [("path",toJson (engine/"llama-server").toString),
      ("sha256",toJson (← hash (engine/"llama-server")))]),
    ("model",Json.mkObj [("path",toJson model.toString),("sha256",toJson (← hash model))]),
    ("runtimeFiles",toJson runtimeFiles),("output",toJson (root/"canary").toString),
    ("requests",toJson #[Json.mkObj [("name",toJson "relevant-first"),
      ("body",request #[relevant,unrelated]),("expectedFirst",toJson (0 : Nat))],
      Json.mkObj [("name",toJson "relevant-second"),
      ("body",request #[unrelated,relevant]),("expectedFirst",toJson (1 : Nat))]])]
  write (root/"canary-plan.json") plan
  guard "local-judgment-canary" #[(root/"probe-build/StudyMain").toString,(root/"canary-plan.json").toString]
def prepareClaimsBuild : IO Unit := do
  idle
  let canary ← finished "local-judgment-canary"
  write (records/"canary.guard.json") canary
  for name in ["result.json","shutdown.json","invocation.json","server.stderr"] do
    IO.FS.writeBinFile (records/("canary-"++name)) (← IO.FS.readBinFile (root/"canary"/name))
  write (records/"canary-controller.json") (Json.mkObj [
    ("executableSha256",toJson (← hash (root/"probe-build/StudyMain"))),
    ("entrySourceSha256",toJson (← hash (root/"source/tools/research/LocalJudgmentProbe.lean"))),
    ("buildSettings",← read (root/"probe-settings.json"))])
  check (!(← (root/"claims-source").pathExists) && !(← (root/"claims-build").pathExists))
    "preserve earlier recorded-claim numerical probe"
  discard <| command "/bin/cp" #["-cR",(root/"source").toString,(root/"claims-source").toString]
  IO.FS.writeFile (root/"claims-source/tools/research/LocalJudgmentProbe.lean")
    (← IO.FS.readFile (project/"tools/research/LocalJudgmentProbe.lean"))
  let settings := (← read (root/"probe-settings.json"))
    |>.setObjVal! "project" (toJson (root/"claims-source").toString)
    |>.setObjVal! "core" (toJson (root/"claims-source").toString)
    |>.setObjVal! "output" (toJson (root/"claims-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"probe-build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"probe-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"probe-build/tools_research_LocalJudgmentProbe.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"probe-build/object-mapping.json").toString)
  write (root/"claims-settings.json") settings
  let definitions ← IO.ofExcept ((← read (project/"docs/practical-runtime/complete-delivery-cohort/task-definitions.json")).getArr?)
  write (root/"prompts.json") (toJson (definitions.map (·.getObjValD "prompt")))
  let integrity ← read (project/"docs/practical-runtime/complete-delivery-cohort/selector-input/journal-integrity.json")
  write (root/"original.json") (Json.mkObj [
    ("path",toJson (base/"practical-runtime/selector-input/originals.json").toString),
    ("sha256",integrity.getObjValD "originalExportSha256")])
  write (records/"claims-policy.json") (Json.mkObj [
    ("documents",toJson "all nonempty double-newline paragraphs of recorded non-native outcomes, with their recorded work"),
    ("questions",← read (root/"prompts.json")),("original",← read (root/"original.json")),
    ("selectionOrRequiredEvidenceReadByPreparer",toJson false),("contextTokens",toJson (4096 : Nat)),
    ("thresholdOrTopKSelection",toJson false),("productChanged",toJson false)])
  guard "local-judgment-claims-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"claims-settings.json").toString]
def prepareClaims : IO Unit := do
  idle
  write (records/"claims-build.guard.json") (← finished "local-judgment-claims-build")
  guard "local-judgment-claims-inputs" #[(root/"claims-build/StudyMain").toString,"prepare-claims",
    (root/"canary-plan.json").toString,(root/"original.json").toString,(root/"prompts.json").toString,
    (root/"claims-inputs").toString]
def runClaims : IO Unit := do
  idle
  write (records/"claims-inputs.guard.json") (← finished "local-judgment-claims-inputs")
  guard "local-judgment-claims" #[(root/"claims-build/StudyMain").toString,
    (root/"claims-inputs/plan.json").toString]
def claimOnly : IO Unit := do
  idle
  write (records/"claims.guard.json") (← finished "local-judgment-claims")
  let captured ← read (root/"claims-inputs/claims.json")
  let claims ← IO.ofExcept (captured.getObjValAs? (Array Json) "claims")
  let paragraphs ← claims.mapM fun claim => IO.ofExcept (claim.getObjValAs? String "paragraph")
  let control ← read (root/"claims-inputs/plan.json")
  let requests ← IO.ofExcept (control.getObjValAs? (Array Json) "requests")
  let mut revised := #[]
  for request in requests do
    let body := request.getObjValD "body"
    let documents ← IO.ofExcept (body.getObjValAs? (Array String) "documents")
    check (documents.size == paragraphs.size) "claim comparison changed the candidate domain"
    revised := revised.push (request.setObjVal! "body" (body.setObjVal! "documents" (toJson paragraphs)))
  write (root/"claim-only-plan.json") (control.setObjVal! "requests" (toJson revised)
    |>.setObjVal! "output" (toJson (root/"claim-only").toString))
  write (records/"claim-only-policy.json") (Json.mkObj [
    ("change",toJson "remove the shared past-work prefix from every document; preserve every complete paragraph"),
    ("allQuestionsAndClaimsPreserved",toJson true),("modelAndNumericalSettingsPreserved",toJson true),
    ("controlInputSha256",toJson (← hash (root/"claims-inputs/plan.json"))),
    ("claimOnlyInputSha256",toJson (← hash (root/"claim-only-plan.json"))),
    ("claimsSha256",toJson (← hash (root/"claims-inputs/claims.json"))),
    ("controllerSha256",toJson (← hash (root/"claims-build/StudyMain"))),
    ("requiredEvidenceListOrSelectedBodyUsed",toJson false),("adopted",toJson false)])
  guard "local-judgment-claim-only" #[(root/"claims-build/StudyMain").toString,
    (root/"claim-only-plan.json").toString]
def groundingBuild : IO Unit := do
  idle
  write (records/"claim-only.guard.json") (← finished "local-judgment-claim-only")
  IO.FS.writeFile (root/"claims-source/tools/research/LocalJudgmentGrounding.lean")
    (← IO.FS.readFile (project/"tools/research/LocalJudgmentGrounding.lean"))
  let settings := (← read (root/"claims-settings.json"))
    |>.setObjVal! "output" (toJson (root/"grounding-build").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.LocalJudgmentGrounding")
    |>.setObjVal! "parents" (toJson #[(root/"claims-build").toString,
      (base/"practical-runtime/source-snapshot/build").toString])
  write (root/"grounding-settings.json") settings
  guard "local-judgment-grounding-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"grounding-settings.json").toString]
def grounding (tag : String := "local-judgment-grounding-build") : IO Unit := do
  idle
  write (records/"grounding-build.guard.json") (← finished tag)
  guard "local-judgment-grounding" #[(root/"grounding-build/StudyMain").toString,
    (root/"claims-inputs/claims.json").toString,(root/"claims-inputs/run/result.json").toString,
    (root/"claim-only/result.json").toString,
    (project/"docs/candidates/project-query-receipt/before-delivery.json").toString,
    (base/"practical-runtime/project-query-receipt/captured-inputs/diagnostic/selection.json").toString,
    (records/"grounding.json").toString]
def finish : IO Unit := do
  idle
  write (records/"grounding.guard.json") (← finished "local-judgment-grounding")
  let mut summary := #[]
  let mut requests := #[]
  let mut totalTokens := 0
  for (name,directory) in [("canary",root/"canary"),("work-and-claim",root/"claims-inputs/run"),
      ("claim-only",root/"claim-only")] do
    let result ← read (directory/"result.json")
    let shutdown ← read (directory/"shutdown.json")
    check (shutdown.getObjValD "pipesJoined" == toJson true && shutdown.getObjValD "ipcRemoved" == toJson true)
      "numerical server still owns resources"
    let measurements ← IO.ofExcept (result.getObjValAs? (Array Json) "measurements")
    let mut pairs := 0
    let mut tokens := 0
    for number in [:measurements.size] do
      let measured := measurements[number]!
      let requestPath := directory/s!"request-{number}.json"
      check (toJson (← hash requestPath) == measured.getObjValD "requestSha256")
        "saved numerical request differs from actual input"
      requests := requests.push (Json.mkObj [("variant",toJson name),("name",measured.getObjValD "name"),
        ("sha256",measured.getObjValD "requestSha256"),("utf8Request",toJson (← IO.FS.readFile requestPath))])
      pairs := pairs+(← IO.ofExcept ((measured.getObjValD "response").getObjValAs? (Array Json) "results")).size
      tokens := tokens+(← IO.ofExcept (((measured.getObjValD "response").getObjValD "usage").getObjValAs? Nat "total_tokens"))
    let stderr ← IO.FS.readFile (directory/"server.stderr")
    let truncations ← ((stderr.splitOn "truncated = ").drop 1).mapM fun tail => do
      let some value := (String.ofList (tail.toList.takeWhile Char.isDigit)).toNat? |
        throw (IO.userError "invalid truncation counter")
      pure value
    check (truncations.length == pairs && truncations.all (· == 0)) "numerical engine truncated an input or omitted a pair"
    for file in ["result.json","shutdown.json","server.stderr"] do
      IO.FS.writeBinFile (records/(name++"-"++file)) (← IO.FS.readBinFile (directory/file))
    totalTokens := totalTokens+tokens
    summary := summary.push (Json.mkObj [("variant",toJson name),("startupMs",result.getObjValD "startupMs"),
      ("pairs",toJson pairs),("engineReportedTotalTokens",toJson tokens),("allPairsUntruncated",toJson true),
      ("guard",← finished (if name == "canary" then "local-judgment-canary" else
        if name == "claim-only" then "local-judgment-claim-only" else "local-judgment-claims"))])
  write (records/"requests.json") (toJson requests)
  IO.FS.writeBinFile (records/"claims.json") (← IO.FS.readBinFile (root/"claims-inputs/claims.json"))
  write (records/"summary.json") (Json.mkObj [("runs",toJson summary),
    ("localEngineReportedTotalTokens",toJson totalTokens),("answeringModelCalls",toJson (0 : Nat)),
    ("productChanged",toJson false),("actualHookDeliveryMeasuredWithJudge",toJson false),("adopted",toJson false)])
  let auditor := project/"tools/research/StudyBuildClosureAudit.lean"
  for (build,label) in [(root/"probe-build","canary"),(root/"claims-build","numerical"),(root/"grounding-build","grounding")] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditor.toString,
      "inspect",build.toString,(records/(label++"-native.json")).toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditor.toString,
    "component-sources",(base/"practical-runtime/source-snapshot/build").toString,(root/"grounding-build").toString,
    (records/"grounding-sources.json").toString,"Eggshell.SynapseSource","Eggshell.Synapses"]
  let seedPlan ← read (project/"docs/candidates/project-query-receipt/plan.json")
  let original ← IO.ofExcept (seedPlan.getObjValAs? String "original")
  for (name,digest) in ← IO.ofExcept (seedPlan.getObjValAs? (Array (String × String)) "originalFiles") do
    check ((← hash (System.FilePath.mk original/name)) == digest) "accepted seed changed during numerical probe"
  check ((← hash (base/"practical-runtime/source-snapshot/build/StudyMain")) ==
    "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534") "retained product changed"
  let mut removed := #[]
  for name in ["source","probe-build","claims-source","claims-build","grounding-build","canary","claims-inputs","claim-only"] do
    let path := root/name
    check ((← path.symlinkMetadata).type == .dir) "retire only an owned experiment directory"
    discard <| command "/bin/rm" #["-rf",path.toString]
    check (!(← path.pathExists)) "ended numerical fixture still exists"
    removed := removed.push path.toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditor.toString,
    "inspect",(base/"practical-runtime/source-snapshot/build").toString,(records/"retained-product-native.json").toString]
  write (records/"retired.json") (Json.mkObj [("removed",toJson removed),("archived",toJson false),
    ("modelAndNativeEngineRetainedForNextProbe",toJson true),("acceptedSeedUnchanged",toJson true)])
end LocalJudgmentStudy
def main : List String → IO Unit
  | ["prepare"] => LocalJudgmentStudy.prepare
  | ["download"] => LocalJudgmentStudy.download
  | ["prepare-probe"] => LocalJudgmentStudy.prepareProbe
  | ["run-probe"] => LocalJudgmentStudy.runProbe
  | ["run-probe",tag] => LocalJudgmentStudy.runProbe tag
  | ["prepare-claims-build"] => LocalJudgmentStudy.prepareClaimsBuild
  | ["prepare-claims"] => LocalJudgmentStudy.prepareClaims
  | ["run-claims"] => LocalJudgmentStudy.runClaims
  | ["claim-only"] => LocalJudgmentStudy.claimOnly
  | ["grounding-build"] => LocalJudgmentStudy.groundingBuild
  | ["grounding"] => LocalJudgmentStudy.grounding
  | ["grounding",tag] => LocalJudgmentStudy.grounding tag
  | ["finish"] => LocalJudgmentStudy.finish
  | _ => throw (IO.userError "LocalJudgmentStudy prepare|download")
