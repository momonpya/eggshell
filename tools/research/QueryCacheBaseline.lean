import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
import Std.Data.HashSet
open Lean

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def root : System.FilePath := study / "shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def baseline : System.FilePath := root / "fact-deferred-runtime-build"
private def frozen : System.FilePath := root / "query-cache-baseline-core"
private def output : System.FilePath := project / "docs/candidates/query-cache-llvm"

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def literalPath (source : String) (name : String) : Except String String := do
  unless !name.startsWith "/" do throw "absolute literal input"
  let mut parts := (source.splitOn "/").dropLast
  for part in name.splitOn "/" do
    match part with
    | "" | "." => pure ()
    | ".." =>
      if parts.isEmpty then throw "literal input escaped the reconstructed tree"
      parts := parts.dropLast
    | _ => parts := parts ++ [part]
  unless !parts.isEmpty do throw "literal input names the reconstructed root"
  return String.intercalate "/" parts

private def retain (files : Std.HashMap String String) (path text : String) : Except String (Std.HashMap String String) := do
  if let some previous := files[path]? then
    unless previous == text do throw s!"inconsistent compiled source witnesses: {path}"
  return files.insert path text

private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot identify the selected runtime"
  return (result.stdout.splitOn " ").headD ""

private partial def fillHelperSources (origin destination : System.FilePath) : IO Nat := do
  IO.FS.createDirAll destination
  let mut count := 0
  for entry in ← origin.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir && ![".lake",".git"].contains entry.fileName then
      count := count+(← fillHelperSources entry.path (destination / entry.fileName))
    else if kind == .file && entry.fileName.endsWith ".lean" && !(← (destination / entry.fileName).pathExists) then
      IO.FS.writeFile (destination / entry.fileName) (← IO.FS.readFile entry.path)
      count := count+1
  return count

def main (args : List String) : IO Unit := do
  if args == ["verify-reconstruction"] then
    let selected ← read (output / "source-reconstruction.json")
    let names : Array String ← IO.ofExcept (selected.getObjValAs? _ "nativeModules")
    let build ← read (baseline / "build.json")
    let mapPath ← IO.ofExcept ((build.getObjValD "settings").getObjValAs? String "objectModules")
    let mut modules ← IO.ofExcept ((← read (.mk mapPath)).getObj?)
    for entry in ← IO.ofExcept ((build.getObjValD "modules").getArr?) do
      modules := modules.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
    let mut checked := 0
    let mut literalCount := 0
    let keyed := "Eggshell/KeyedSearchProvider.lean"
    let entry := "def run (arguments : List String) : IO UInt32 := IO.FS.withTempDir fun scratch => do\n"
    let oldOptions := "SearchProvider.parse {cache := scratch,models := layout.models} arguments"
    for line in (← IO.FS.readFile (baseline / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let object ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      let some moduleValue := modules[object]? | continue
      let name ← IO.ofExcept moduleValue.getStr?
      if !names.contains name then continue
      let path := name.replace "." "/" ++ ".lean"
      let (text,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read ((System.FilePath.mk object).withExtension "source")))
      let expected := if path == keyed then text.replace entry (entry ++ "  let scratch ← IO.FS.realPath scratch\n")
        |>.replace oldOptions "SearchProvider.parse {cache := scratch,queryTemporary := some (scratch / \"queries\"),models := layout.models} arguments"
        else text
      check ((← IO.FS.readFile (frozen / path)) == expected) s!"reconstructed source changed unexpectedly: {path}"
      for (name,content) in literals do
        let target ← IO.ofExcept (literalPath path name)
        let expected := if target == keyed then content.replace entry (entry ++ "  let scratch ← IO.FS.realPath scratch\n")
          |>.replace oldOptions "SearchProvider.parse {cache := scratch,queryTemporary := some (scratch / \"queries\"),models := layout.models} arguments"
          else content
        check ((← IO.FS.readFile (frozen / target)) == expected) s!"reconstructed literal changed unexpectedly: {target}"
        literalCount := literalCount+1
      checked := checked+1
    check (checked == 185 && names.size == 185) "source comparison omitted native modules"
    IO.FS.writeFile (output / "source-comparison.json") (Json.mkObj [
      ("checkedNativeModules",toJson checked),("checkedLiteralInputs",toJson literalCount),
      ("onlyChangedInput",toJson keyed),("baselineSha256",toJson (← digest (baseline / "StudyMain"))),
      ("candidateSha256",toJson (← digest (root / "query-cache-baseline-build/StudyMain"))),
      ("sourceDbChanged",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
    IO.println "Compared all 185 native module texts and literal inputs; only keyed query-cache initialization differs"
    return
  if args == ["retire-primary-fixture-runtime"] then
    let target := root / "source-lexical-query-runtime-build/StudyMain"
    check ((← digest target) == "bc3581339976ceadc672dfb110639f397d0ed7ba451ae1bd8ef7e1bcff27590c") "wrong completed primary-index fixture runtime"
    let guard ← read (project / "docs/candidates/source-lexical/native-query-hook.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "primary-index fixture not finished"
    let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t",target.toString]}
    check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "completed primary-index runtime is in use"
    let report := output / "retired-completed-runtime.json"
    check (!(← report.pathExists)) "preserve primary runtime retirement"
    IO.FS.writeFile report (Json.mkObj [("target",toJson target.toString),("sha256",toJson (← digest target)),
      ("sourceObjectsInterfacesAndSuccessfulHookRecordsRetained",toJson true),
      ("baselineAndCurrentQueryOnlyRuntimeRetained",toJson true),("archiveCreated",toJson false)]).pretty
    IO.FS.removeFile target
    IO.println "Deleted completed primary-index fixture executable; complete source/object/interface evidence retained"
    return
  if args == ["prepare-hook-build"] || args == ["prepare-support-build"] || args == ["prepare-profile-build"] then
    let helperSources ← fillHelperSources (root / "core") frozen
    let profile := args == ["prepare-profile-build"]
    let diagnostic := args == ["prepare-support-build"] || profile
    let parent := root / (if diagnostic then "readonly-query-trial-build" else "query-cache-baseline-build")
    let build ← read (parent / "build.json")
    let prior := build.getObjValD "settings"
    let mapPath ← IO.ofExcept (prior.getObjValAs? String "objectModules")
    let mut modules ← IO.ofExcept ((← read (.mk mapPath)).getObj?)
    for entry in ← IO.ofExcept ((build.getObjValD "modules").getArr?) do
      modules := modules.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
    let label := if profile then "readonly-query-profile" else if diagnostic then "missing-support-audit" else "readonly-query-trial"
    let map := root / (label ++ "-objects.json")
    IO.FS.writeFile map (Json.obj modules).pretty
    let settings := prior.setObjVal! "project" (toJson project.toString)
      |>.setObjVal! "baselineResponse" (toJson (parent / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (parent / (if diagnostic then "tools_research_ReadOnlyQueryTrial.o" else "Main.o")).toString)
      |>.setObjVal! "objectModules" (toJson map.toString)
      |>.setObjVal! "output" (toJson (root / (label ++ "-build")).toString)
      |>.setObjVal! "mainModule" (toJson (if profile then "tools.research.ProfileReadOnlyQuery" else
        if diagnostic then "tools.research.MissingSupportAudit" else "tools.research.ReadOnlyQueryTrial"))
    let library := frozen / ".lake/build/lib/lean"
    check ((← library.symlinkMetadata).type == .symlink) "expected reconstructed interface link"
    IO.FS.removeFile library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "lib").toString,library.toString]}
    check (linked.exitCode == 0) "cannot reuse reconstructed native interfaces"
    IO.FS.writeFile (root / (label ++ "-build.settings.json")) settings.pretty
    IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
      ("record",toJson (root / (label ++ s!"-build-{← IO.monoNanosNow}.guard.json")).toString),
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("minFreeKiB",toJson (2097152 : Nat)),("limitRssKiB",toJson (3670016 : Nat)),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,(root / (label ++ "-build.settings.json")).toString])]).pretty
    IO.println s!"Prepared readonly hook trial; added {helperSources} helper-only source files without replacing the 185 product inputs"
    return
  check (args == ["prepare"] && !(← frozen.pathExists)) "fresh explicit baseline reconstruction required"
  IO.FS.createDirAll output
  let hash ← digest (baseline / "StudyMain")
  check (hash == "62d637b79abb480ac2bc9c6853d621dc57d92c87a1bd9de31985aeb985357b3b") "wrong LLVM baseline runtime"
  let build ← read (baseline / "build.json")
  let prior := build.getObjValD "settings"
  let mapPath ← IO.ofExcept (prior.getObjValAs? String "objectModules")
  let mut modules ← IO.ofExcept ((← read (.mk mapPath)).getObj?)
  for entry in ← IO.ofExcept ((build.getObjValD "modules").getArr?) do
    modules := modules.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
  let mut files : Std.HashMap String String := {}
  let mut checked := #[]
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (baseline / "Main.dependencies")))
  let needed := Std.HashSet.ofArray (expected.map Prod.fst)
  let mut unused : Array String := #[]
  let mut mainObject := ""
  for line in (← IO.FS.readFile (baseline / "runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let object ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let some moduleValue := modules[object]? | continue
    let name ← IO.ofExcept moduleValue.getStr?
    if !needed.contains name then
      unused := unused.push name
      continue
    check (!(name.splitOn ".").any (fun part => part.isEmpty || part.contains '/' || part.contains '\\')) "invalid source module"
    let path := name.replace "." "/" ++ ".lean"
    let (text,literals) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read ((System.FilePath.mk object).withExtension "source")))
    files ← IO.ofExcept (retain files path text)
    for (name,content) in literals do
      files ← IO.ofExcept (retain files (← IO.ofExcept (literalPath path name)) content)
    checked := checked.push name
    if name == "Main" then mainObject := object
  check (checked.size == 185 && !mainObject.isEmpty) "baseline source reconstruction omitted native inputs"
  let keyed := "Eggshell/KeyedSearchProvider.lean"
  let some original := files[keyed]? | throw (IO.userError "baseline keyed entry source absent")
  let entry := "def run (arguments : List String) : IO UInt32 := IO.FS.withTempDir fun scratch => do\n"
  let oldOptions := "SearchProvider.parse {cache := scratch,models := layout.models} arguments"
  check ((original.splitOn entry).length == 2 && (original.splitOn oldOptions).length == 2)
    "keyed entry does not match the observed initialization omission"
  let updated := original.replace entry (entry ++ "  let scratch ← IO.FS.realPath scratch\n")
    |>.replace oldOptions "SearchProvider.parse {cache := scratch,queryTemporary := some (scratch / \"queries\"),models := layout.models} arguments"
  files := files.insert keyed updated
  IO.FS.createDir frozen
  for (path,text) in files.toArray do
    let destination := frozen / path
    IO.FS.createDirAll destination.parent.get!
    IO.FS.writeFile destination text
  let library := frozen / ".lake/build/lib/lean"
  IO.FS.createDirAll library.parent.get!
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(baseline / "lib").toString,library.toString]}
  check (linked.exitCode == 0) "cannot reuse checked baseline interfaces"
  let label := "query-cache-baseline"
  let map := root / (label ++ "-objects.json")
  IO.FS.writeFile map (Json.obj modules).pretty
  let settings := prior.setObjVal! "project" (toJson frozen.toString)
    |>.setObjVal! "core" (toJson frozen.toString)
    |>.setObjVal! "baselineCore" (toJson frozen.toString)
    |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson mainObject)
    |>.setObjVal! "objectModules" (toJson map.toString)
    |>.setObjVal! "output" (toJson (root / (label ++ "-build")).toString)
    |>.setObjVal! "mainModule" (toJson "Main")
    |>.setObjVal! "force" (toJson (#[] : Array String))
  IO.FS.writeFile (root / (label ++ "-build.settings.json")) settings.pretty
  IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
    ("record",toJson (root / (label ++ s!"-build-{← IO.monoNanosNow}.guard.json")).toString),
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("minFreeKiB",toJson (2097152 : Nat)),("limitRssKiB",toJson (3670016 : Nat)),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,(root / (label ++ "-build.settings.json")).toString])]).pretty
  IO.FS.writeFile (output / "source-reconstruction.json") (Json.mkObj [
    ("baselineSha256",toJson hash),("nativeModules",toJson checked),
    ("linkedButOutsideMainDependencyClosure",toJson unused),
    ("reconstructedFiles",toJson files.size),("changedSource",toJson keyed),
    ("otherSourcesAndLiteralsExact",toJson true),("sourceDbChanged",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Reconstructed all 185 checked native module sources; only keyed query-cache initialization differs"
