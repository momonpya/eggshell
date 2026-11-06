import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- Inspect the native objects actually selected by the linker. The current
entrypoint's sealed inputs are the oracle, rather than the builder's changed
flags or inherited interface symlinks. Report module names, never source text. -/
private def inspect (directory : System.FilePath) : IO Json := do
  let build ← read (directory / "build.json")
  let settings := build.getObjValD "settings"
  let mainName ← IO.ofExcept (settings.getObjValAs? String "mainModule")
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read
    (directory / (mainName.replace "." "_" ++ ".dependencies"))))
  let inputs := expected.foldl (fun found (name,stamp) => found.insert name stamp)
    ({} : Std.HashMap String String)
  let effective := directory / "object-mapping.json"
  let mapping ← if ← effective.pathExists then read effective
    else read (.mk (← IO.ofExcept (settings.getObjValAs? String "objectModules")))
  let mut modules : Std.HashMap String String := {}
  for (path,name) in (← IO.ofExcept mapping.getObj?).toArray do
    modules := modules.insert path (← IO.ofExcept name.getStr?)
  for row in ← IO.ofExcept ((build.getObjValD "modules").getArr?) do
    modules := modules.insert (← IO.ofExcept (row.getObjValAs? String "object"))
      (← IO.ofExcept (row.getObjValAs? String "module"))
  let mut checked := 0
  let mut failures := #[]
  for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let some name := modules[path]? | continue
    unless inputs.contains name do continue
    checked := checked+1
    let evidence := (System.FilePath.mk path).withExtension "dependencies"
    if !(← evidence.pathExists) then
      failures := failures.push (Json.mkObj [("module",toJson name),("reason",toJson "native dependency evidence missing")])
      continue
    let dependencies : Array (String × String) ← IO.ofExcept (fromJson? (← read evidence))
    if let some builder := inputs["@builder"]? then
      unless (Std.HashMap.ofArray dependencies)["@builder"]? == some builder do
        failures := failures.push (Json.mkObj [("module",toJson name),
          ("reason",toJson "native producer builder identity missing or different")])
    let changed := dependencies.filterMap fun (dependency,stamp) =>
      if inputs[dependency]? == some stamp then none else some dependency
    unless changed.isEmpty do
      failures := failures.push (Json.mkObj [("module",toJson name),("changedInputs",toJson changed)])
  unless checked > 0 do throw (IO.userError "native dependency audit was vacuous")
  return Json.mkObj [("build",toJson directory.toString),("checkedNativeObjects",toJson checked),
    ("failures",Json.arr failures),("consistent",toJson failures.isEmpty)]

private def sourceWitnesses (directory : System.FilePath) : IO (String × Std.HashMap String String) := do
  let build ← read (directory/"build.json")
  let entry ← IO.ofExcept ((build.getObjValD "settings").getObjValAs? String "mainModule")
  let mapping ← read (directory/"object-mapping.json")
  let mut modules : Std.HashMap String String := {}
  for (object,name) in (← IO.ofExcept mapping.getObj?).toArray do
    modules := modules.insert object (← IO.ofExcept name.getStr?)
  for row in ← IO.ofExcept ((build.getObjValD "modules").getArr?) do
    modules := modules.insert (← IO.ofExcept (row.getObjValAs? String "object"))
      (← IO.ofExcept (row.getObjValAs? String "module"))
  let mut found : Std.HashMap String String := {}
  for line in (← IO.FS.readFile (directory/"runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let object ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let some name := modules[object]? | do
      if ← ((System.FilePath.mk object).withExtension "source").pathExists then
        throw (IO.userError ("selected native source has no module mapping: "++object))
      continue
    if name == entry then continue
    let witness := (System.FilePath.mk object).withExtension "source"
    unless ← witness.pathExists do throw (IO.userError ("native source witness missing: "++name))
    let bytes ← IO.FS.readFile witness
    if let some old := found[name]? then
      unless old == bytes do throw (IO.userError ("duplicate native source: "++name))
    found := found.insert name bytes
  unless found.size > 0 do throw (IO.userError "native source comparison was vacuous")
  return (entry,found)

def main (args : List String) : IO Unit := do
  if let "compare-sources"::parent::candidate::output::allowed := args then
    let path : System.FilePath := .mk output
    unless !(← path.pathExists) do throw (IO.userError "preserve native source comparison")
    let (oldEntry,old) ← sourceWitnesses (.mk parent)
    let (newEntry,current) ← sourceWitnesses (.mk candidate)
    let additions := allowed.filterMap fun name =>
      if name.startsWith "+" then some (name.drop 1 |>.toString) else none
    let allowed := allowed.filter fun name => !name.startsWith "+"
    let mut changed := #[]
    let mut removed := #[]
    let mut added := #[]
    for (name,bytes) in old do
      match current[name]? with
      | none => removed := removed.push name
      | some actual => if actual != bytes then changed := changed.push name
    for (name,_) in current do
      unless old.contains name do added := added.push name
    let decode (bytes : String) : IO (String × Array (String × String)) :=
      IO.ofExcept (Json.parse bytes >>= fromJson?)
    let mut expectedLiterals : Array (String × String) := #[]
    for name in allowed do
      let some before := old[name]? | throw (IO.userError "declared parent source absent")
      let some after := current[name]? | throw (IO.userError "declared candidate source absent")
      expectedLiterals := expectedLiterals.push ((← decode before).1,(← decode after).1)
    let mut direct := #[]
    let mut literalContainers := #[]
    let mut literalsApproved := true
    for name in changed do
      let before ← decode old[name]!
      let after ← decode current[name]!
      if before.1 != after.1 then direct := direct.push name
      if before.2.map (·.1) != after.2.map (·.1) then literalsApproved := false
      let mut paths := #[]
      for (left,right) in before.2.zip after.2 do
        if left.2 != right.2 then
          paths := paths.push right.1
          -- An implementation-identity container may embed changed source.
          -- Accept only the exact before/after bytes of a declared change.
          unless expectedLiterals.contains (left.2,right.2) do literalsApproved := false
      if !paths.isEmpty then literalContainers := literalContainers.push (name,paths)
    let ok := removed.isEmpty && added.size == additions.length && added.all (additions.contains ·) &&
      direct.size == allowed.length &&
      direct.all (allowed.contains ·) && literalsApproved
    let runtimeHash (directory : String) : IO String := do
      let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",directory++"/StudyMain"]}
      unless result.exitCode == 0 do throw (IO.userError "cannot bind source audit to runtime")
      return (result.stdout.splitOn " ").headD ""
    IO.FS.writeFile path (Json.mkObj [("parentEntry",toJson oldEntry),("candidateEntry",toJson newEntry),
      ("parentRuntimeSha256",toJson (← runtimeHash parent)),("candidateRuntimeSha256",toJson (← runtimeHash candidate)),
      ("parentModules",toJson old.size),("candidateModules",toJson current.size),
      ("changedSourcesAndLiteralInputs",toJson (changed.qsort (· < ·))),
      ("directSourceChanges",toJson (direct.qsort (· < ·))),("literalContainers",toJson literalContainers),
      ("literalChangesExactlyMatchDeclaredSourceBytes",toJson literalsApproved),
      ("removed",toJson removed),("added",toJson added),("declaredAddedModules",toJson additions),
      ("exactExpectedChangeSet",toJson ok)]).pretty
    unless ok do throw (IO.userError "native source comparison changed more than the declared candidate")
    return
  if let ["inspect",build,output] := args then
    let path := System.FilePath.mk output
    unless !(← path.pathExists) do throw (IO.userError "preserve native closure evidence")
    let report ← inspect (.mk build)
    IO.FS.writeFile path report.pretty
    unless report.getObjValD "consistent" == toJson true do
      throw (IO.userError "native link inputs are inconsistent")
    IO.println report.compress
    return
  let [oldBuild,newBuild,output] := args | throw (IO.userError "old build, repaired build and new output required")
  let path := System.FilePath.mk output
  unless !(← path.pathExists) do throw (IO.userError "preserve native closure evidence")
  let old ← inspect (.mk oldBuild)
  let repaired ← inspect (.mk newBuild)
  unless old.getObjValD "consistent" == toJson false && repaired.getObjValD "consistent" == toJson true do
    throw (IO.userError "native closure audit did not reject the stale build and accept the repaired one")
  let report := Json.mkObj [("staleBuild",old),("repairedBuild",repaired),
    ("answeringModelCalls",toJson (0 : Nat)),("actualHookCalls",toJson (0 : Nat))]
  IO.FS.writeFile path report.pretty
  IO.println report.compress
