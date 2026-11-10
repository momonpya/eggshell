import tools.research.StudyLocal
open Lean StudyLocal
def trial := base/"register-rounds"
def selected := base/"current-six/stable-source-rows/build"
def source := trial/"source"
def build := trial/"build"
def records := project/"docs/candidates/register-rounds"
def entry := "tools.research.RegisterRoundsChecks"
def candidate := "tools.research.RegisterRoundsDigest"
def clean (tag : String) : IO Json := do
  let value ← finished tag
  check (value.getObjValD "guardTriggered" == toJson false && value.getObjValD "reason" == Json.null)
    "supervisor did not finish normally"
  return value

partial def leaves (path : System.FilePath) : IO (Array System.FilePath) := do
  let mut out := #[]
  for file in ← path.readDir do
    let kind := (← file.path.symlinkMetadata).type
    if kind == .dir then out := out++(← leaves file.path)
    else if kind == .file then out := out.push file.path
  return out

partial def protect (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if !(← path.pathExists) then return
  let actual ← IO.FS.realPath path
  if (← seen.get).contains actual.toString then return
  seen.modify (·.insert actual.toString)
  if (← actual.metadata).type == .dir then
    for file in ← actual.readDir do protect file.path seen

def unusedCompilerPlan : IO (Array System.FilePath × Nat) := do
  let reachable ← IO.mkRef ({} : Std.HashSet String)
  for root in #[selected/"lib",selected.parent.get!/"source",build/"lib",source,base/"study-local-lib",
      base/"byte-pages-runtime-build/lib",project/".lake/build/lib",
      System.FilePath.mk "/Users/ovm/Code/eggshell/.lake/build/lib"] do
    protect root reachable
  for root in #[selected,build,base/"byte-pages-runtime-build"] do
    for line in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let value ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      if value.endsWith ".o" then
        if !(← (System.FilePath.mk value).pathExists) then
          check (root == base/"byte-pages-runtime-build") ("retained native object is absent: "++value)
          continue
        protect (.mk value) reachable
  let keep ← reachable.get
  let mut out := #[]
  let mut bytes := 0
  for path in ← leaves base do
    if keep.contains path.toString then continue
    let mut object := path
    if !path.toString.endsWith ".o" then
      let parts := path.toString.splitOn "/lib/"
      if parts.length != 2 then continue
      let relative := parts[1]!
      let suffixes := [".olean.private",".olean.server",".olean",".ir.sig",".ir",".ilean"]
      let some suffix := suffixes.find? (fun suffix => relative.endsWith suffix) | continue
      object := .mk (parts[0]!++"/"++((relative.dropEnd suffix.length).copy.replace "/" "_")++".o")
      if keep.contains object.toString then continue
    -- Only generated files of stamped Lean modules are eligible. Actual
    -- linked objects, resolved library/source inputs and foreign adapters
    -- remain protected. Source and transitive stamps are kept for recovery.
    if !(← (object.withExtension "source").pathExists) ||
        !(← (object.withExtension "dependencies").pathExists) then continue
    out := out.push path
    bytes := bytes+(← path.metadata).byteSize.toNat
  return (out,bytes)

def generated (original : String) : IO String := do
  check ((original.splitOn "Eggshell.Blake3").length == 3) "unexpected actual namespace boundary"
  let renamed := original.replace "Eggshell.Blake3" "Eggshell.Research.RegisterRoundsDigest"
  let marker := "\nstructure Source where\n"
  let binding := "\n@[csimp] theorem seven_rounds_compiled : @sevenRounds = @Eggshell.Research.RegisterRounds.optimized := by\n  have lane : @Eggshell.Research.RegisterMix.reference = @g := by\n    rw [register_mix_compiled]\n    funext state a b c d mx my\n    exact (Eggshell.Research.RegisterMix.optimized_exact state a b c d mx my).symm\n  have one : @Eggshell.Research.RegisterRounds.referenceRound = @round := by\n    funext state message\n    simp only [Eggshell.Research.RegisterRounds.referenceRound,Eggshell.Research.RegisterRounds.referenceRoundState,round,lane]\n  have shuffle : @Eggshell.Research.RegisterRounds.referencePermute = @permute := by rfl\n  funext state message\n  have same : Eggshell.Research.RegisterRounds.referenceSeven state message = sevenRounds state message := by\n    simp only [Eggshell.Research.RegisterRounds.referenceSeven,sevenRounds,one,shuffle]\n  exact same.symm.trans (Eggshell.Research.RegisterRounds.optimized_exact state message).symm\n"
  check ((renamed.splitOn marker).length == 2) "one pre-consumer binding boundary required"
  return renamed.replace "public import tools.research.RegisterMix" "public import tools.research.RegisterMix\npublic import tools.research.RegisterRounds"
    |>.replace marker (binding++marker)

def main (args : List String) : IO Unit := do
  if args == ["space"] then
    idle
    let mut affected := #[]
    let mut seen : Std.HashSet String := {}
    let mut estimated := 0
    for line in (← IO.FS.readFile (selected/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let object : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if !object.toString.endsWith ".o" ||
          [some "storage-sync.o",some "adapter.o"].contains object.fileName then continue
      -- This is a space estimate, not the closure audit. Foreign objects do
      -- not have Lean input stamps; their bytes are not estimated as rebuilt.
      if !(← (object.withExtension "source").pathExists) then continue
      let deps : Array (String × String) ← IO.ofExcept (fromJson? (← read (object.withExtension "dependencies")))
      if !(deps.any (·.1 == "Eggshell.Blake3")) then continue
      affected := affected.push object.toString
      let moduleName := object.fileStem.get! |>.replace "_" "."
      let interface := object.parent.get!/"lib"/(moduleName.replace "." "/")
      for path in #[object,interface.withExtension "olean",interface.withExtension "olean.private",
          interface.withExtension "olean.server",interface.withExtension "ir",interface.withExtension "ir.sig"] do
        if !(← path.pathExists) then continue
        let actual ← IO.FS.realPath path
        if seen.contains actual.toString then continue
        seen := seen.insert actual.toString
        estimated := estimated+(← actual.metadata).byteSize.toNat
    let mut ended := #[]
    let mut retiredBytes := 0
    for name in ["controller-build","preparation-closure-build"] do
      let root := base/"current-six/fixed-sequence"/name
      for file in ← root.readDir do
        if !file.fileName.endsWith ".o" then continue
        check ((← file.path.symlinkMetadata).type == .file) "only owned ended native objects"
        let size := (← file.path.metadata).byteSize.toNat
        ended := ended.push (file.path.toString,size)
        retiredBytes := retiredBytes+size
    let (unused,unusedBytes) ← unusedCompilerPlan
    write (records/"space-plan.json") (Json.mkObj [("affectedObjects",toJson affected),
      ("estimatedExistingAffectedObjectAndInterfaceBytes",toJson estimated),
      ("endedHelperObjects",toJson ended),("endedHelperObjectBytes",toJson retiredBytes),
      ("unreferencedNativeObjects",toJson (unused.map (·.toString))),
      ("unreferencedNativeObjectBytes",toJson unusedBytes),
      ("deleted",toJson false)])
  else if args == ["retire-unused"] then
    idle
    check (!(← (records/"retired-unused.json").pathExists)) "preserve retirement evidence"
    let (files,bytes) ← unusedCompilerPlan
    let planned ← read (records/"space-plan.json")
    check (planned.getObjValD "unreferencedNativeObjects" == toJson (files.map (·.toString)) &&
      planned.getObjValD "unreferencedNativeObjectBytes" == toJson bytes) "retirement plan changed"
    let live ← command "/bin/ps" #["-axo","command="]
    check (!(live.contains "StudyBuildMain.lean")) "native compiler is active"
    let mut retained := #[selected/"StudyMain",build/"StudyMain",
      base/"current-six/fixed-sequence/controller-build/StudyMain",
      base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",
      base/"byte-pages-prefix/libexec/eggshell",base/"snapshot-scheduling/work/work.egg/head"]
    for topic in [1,2,3] do
      retained := retained.push (base/"snapshot-scheduling/diagnostic"/("topic-"++toString topic)/"body.txt")
    let hashes ← retained.mapM hash
    let before ← command "/bin/df" #["-Pk",base.toString]
    -- Every target was recomputed from the live source/library/link graph.
    -- Keep its source and transitive stamp; no DB, source, executable, model,
    -- symlink, or resolved active library input is a retirement target.
    for file in files do
      check ((← file.symlinkMetadata).type == .file && !live.contains file.toString)
        "retirement target is not an idle owned generated file"
    write (records/"retired-unused.json") (Json.mkObj [("state",toJson "planned"),
      ("files",toJson (files.map (·.toString))),("logicalBytes",toJson bytes),
      ("protectedInputs",toJson (retained.zip hashes)),("archiveCreated",toJson false)])
    for file in files do IO.FS.removeFile file
    check ((← retained.mapM hash) == hashes) "protected artifact changed during retirement"
    write (records/"retired-unused.json") (Json.mkObj [("state",toJson "finished"),
      ("files",toJson (files.map (·.toString))),("logicalBytes",toJson bytes),
      ("protectedInputs",toJson (retained.zip hashes)),("protectedHashesUnchanged",toJson true),
      ("beforeFreeSpace",toJson before),("afterFreeSpace",toJson (← command "/bin/df" #["-Pk",base.toString])),
      ("sourceAndTransitiveStampsKept",toJson true),("archiveCreated",toJson false),
      ("retiredInputsRebuildableOnlyAfterRegeneration",toJson true)])
  else if args.head? == some "runtime-source" then
    let [_,path] := args | throw (IO.userError "runtime-source <linked baseline source>")
    let original ← IO.FS.readFile (.mk path)
    (← IO.getStdout).putStr ((← generated original).replace "Eggshell.Research.RegisterRoundsDigest" "Eggshell.Blake3")
  else if args == ["setup"] then
    idle
    check ((← hash (selected/"StudyMain")) == "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e") "selected product changed"
    check (!(← trial.pathExists)) "fresh component study required"
    IO.FS.createDirAll records
    materialize selected source build entry "register-rounds-settings.json"
    for name in ["RegisterRounds","RegisterRoundsChecks"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    let objects ← ((← IO.FS.readFile (selected/"runtime.rsp")).splitOn "\n").filterMapM fun row => do
      if row.trimAscii.isEmpty then return none
      let object ← IO.ofExcept (Json.parse row >>= Json.getStr?)
      return if object.endsWith "/Eggshell_Blake3.o" then some (System.FilePath.mk object) else none
    let [object] := objects | throw (IO.userError "one actual linked Blake3 object required")
    let witness := object.withExtension "source"
    let (original,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read witness))
    check (original == (← IO.FS.readFile (source/"Eggshell/Blake3.lean"))) "materialized baseline differs from its linked source witness"
    write (records/"baseline-witness.json") (Json.mkObj [("object",toJson object.toString),
      ("objectSha256",toJson (← hash object)),("witness",toJson witness.toString),
      ("witnessSha256",toJson (← hash witness)),("materializedSourceExactlyMatches",toJson true)])
    check literals.isEmpty "unexpected embedded Blake3 source inputs"
    IO.FS.writeFile (source/"tools/research/RegisterRoundsDigest.lean") (← generated original)
    write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (selected/"StudyMain"))),
      ("priorTurn",toJson "progress:99 canonical hooks;winner-width only1.950% whole-wave benefit,unadopted and retired"),
      ("pastTrialsNotRepeated",toJson "selector-only pool,plain cue buckets,inline-mix13-15% micro improvement"),
      ("hypothesis",toJson "fixed16-lane state/message records eliminate repeated32-word array mutations and message arrays across56mixes;retain7round calls to bound compiler expansion"),
      ("proofGate",toJson "generic complete array equality;separate definally-identical reference bound to linked product source"),
      ("nativeControls",toJson "18 lengths,knownempty/abc,foursegmentboundaries,framedfields,safe non16 array lengths,fourlane patterns"),
      ("timing",toJson "4096bytesx128 and262144bytesx8;AB/BA/AB;IO input read after clock;all output bytes compared"),
      ("componentOnly",toJson true),("wholeHookOrCapacityClaim",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args.head? == some "build" then
    let [_,label] := args | throw (IO.userError "build <unique attempt>")
    idle
    for name in ["RegisterRounds","RegisterRoundsChecks"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    let tag := "register-rounds-build-"++label
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"register-rounds-settings.json").toString]
    write (records/"current-build.json") (Json.mkObj [("tag",toJson tag)])
  else if args.head? == some "audit" then
    let label := args[1]?.getD "initial"
    discard <| clean (← IO.ofExcept ((← read (records/"current-build.json")).getObjValAs? String "tag"))
    let tag := if label == "initial" then "register-rounds-audit" else "register-rounds-audit-"++label
    guard tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/RegisterRoundsStudy.lean").toString,"audit-worker",label]
    write (records/"current-audit.json") (Json.mkObj [("tag",toJson tag),("label",toJson label)])
  else if args.head? == some "audit-worker" then
    let label := args[1]?.getD "initial"
    let suffix := if label == "initial" then "" else "-"++label
    let call := fun parameters => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++parameters)
    discard <| call #["inspect",build.toString,(records/("native"++suffix++".json")).toString]
    discard <| call #["component-sources",selected.toString,build.toString,(records/("sources"++suffix++".json")).toString,
      "Eggshell.Blake3","tools.research.RegisterMix"]
    let names := #["tools.research.RegisterRounds",candidate,entry]
    let parentModules : Array Json ← IO.ofExcept (fromJson? ((← read (selected/"build.json")).getObjValD "modules"))
    let mut witnesses := #[]
    for row in ← IO.ofExcept ((← read (build/"build.json")).getObjValAs? (Array Json) "modules") do
      let name ← IO.ofExcept (row.getObjValAs? String "module")
      check (names.contains name || parentModules.any (fun old => old.getObjValD "module" == toJson name)) "undeclared native module"
    for name in names do
      let (text,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (build/(name.replace "." "_"++".source"))))
      let path := source/(name.replace "." "/"++".lean")
      check (text == (← IO.FS.readFile path) && literals.isEmpty) "native helper differs from its recorded source"
      if name != candidate then
        let expected ← IO.FS.readFile (project/(name.replace "." "/"++".lean"))
        check (text == expected) "reviewed helper changed"
      else
        let recorded ← read (records/"baseline-witness.json")
        let witness : System.FilePath := .mk (← IO.ofExcept (recorded.getObjValAs? String "witness"))
        check (recorded.getObjValD "witnessSha256" == toJson (← hash witness)) "baseline witness changed"
        let (original,originalLiterals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read witness))
        check (originalLiterals.isEmpty && text == (← generated original)) "candidate changed beyond namespace/import/proved compiler binding"
      witnesses := witnesses.push (name,← hash path)
    let symbols ← command "/usr/bin/nm" #["-u",(build/"tools_research_RegisterRoundsDigest.o").toString]
    check (symbols.contains "RegisterRounds_optimized") "candidate compressor does not call the new seven-round function"
    IO.FS.writeFile (records/("consumer-symbols"++suffix++".txt")) symbols
    let nativeSymbols ← command "/usr/bin/nm" #["-n",(build/"tools_research_RegisterRounds.o").toString]
    if label == "packed" then
      let names := nativeSymbols.splitOn "\n"
      check (names.any (·.endsWith "_l_Eggshell_Research_RegisterRounds_packedRound") &&
        !(names.any (fun line => line.endsWith "_l_Eggshell_Research_RegisterRounds_round" ||
          line.endsWith "_l_Eggshell_Research_RegisterRounds_Words_set")))
        "generic setter specification still has executable native code"
    IO.FS.writeFile (records/("kernel-symbols"++suffix++".txt"))
      (String.intercalate "\n" ((nativeSymbols.splitOn "\n").filter fun line =>
        line.contains "RegisterRounds_packedRound" || line.endsWith "_l_Eggshell_Research_RegisterRounds_seven" ||
          line.endsWith "_l_Eggshell_Research_RegisterRounds_optimized"))
    write (records/("runtime"++suffix++".json")) (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("parentSha256",toJson (← hash (selected/"StudyMain"))),("helperSources",toJson witnesses),
      ("generatedCandidateExactlyMatchesLinkedBaselineAndDeclaredBinding",toJson true),("componentOnly",toJson true)])
  else if args.head? == some "run" then
    let label := args[1]?.getD "initial"
    let suffix := if label == "initial" then "" else "-"++label
    let audited ← read (records/"current-audit.json")
    check (audited.getObjValD "label" == toJson label) "audit label differs"
    discard <| clean (← IO.ofExcept (audited.getObjValAs? String "tag"))
    check ((← read (records/("runtime"++suffix++".json"))).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "audited binary changed"
    if label == "packed" then
      write (records/"packed-plan.json") (Json.mkObj [("previousStepVariantRejected",toJson true),
        ("previousResult",toJson "step/component.json"),
        ("previousObservedFailure",toJson "record setter round symbol spans882732bytes and has32-35x allocation heartbeat events;not a speedup"),
        ("change",toJson "proof-only noncomputable indexed specification,one direct fixed-lane round function,proved csimp before seven-round consumers"),
        ("sameInputLengthRepetitionsAndOrdering",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard ("register-rounds-component"++suffix) #[(build/"StudyMain").toString,(trial/("run"++suffix)).toString]
  else if args.head? == some "collect" then
    let label := args[1]?.getD "initial"
    let suffix := if label == "initial" then "" else "-"++label
    let monitor ← clean ("register-rounds-component"++suffix)
    write (records/("component"++suffix++".json")) (Json.mkObj [("guard",monitor),
      ("runtimeSha256",toJson (← hash (build/"StudyMain"))),("report",← read (trial/("run"++suffix)/"report.json"))])
  else throw (IO.userError "setup|build|audit|run|collect")
