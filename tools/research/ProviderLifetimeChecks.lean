import Eggshell.KeyedSearchProvider
import Eggshell.KeyedSearchClient
import Eggshell.ProjectStore
open Lean Eggshell Eggshell.Plugin Eggshell.DB
namespace Eggshell.Research.ProviderLifetimeChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def direct (arguments : List String) (request : KeyedProtocol.Request) : IO Json :=
  IO.FS.withTempDir fun scratch => do
    let scratch ← IO.FS.realPath scratch
    let layout := MiniLM.layout (← Paths.installRoot)
    let options ← IO.ofExcept (SearchProvider.parse {
      cache := scratch,queryTemporary := some (scratch/"queries"),models := layout.models} arguments)
    let child ← if options.mode == "lexical" then pure none else some <$> SearchProvider.encoder options
    try KeyedSearchProvider.handle options child request
    finally if let some child := child then SearchProvider.stopEncoder child
def process (command : List String) (request : KeyedProtocol.Request) : IO Json :=
  SemanticMatcher.withProvider command fun running => SemanticMatcher.withResponseDeadline running do
    SemanticMatcher.write running ((toJson request).compress++"\n")
    IO.ofExcept (Json.parse (← running.child.stdout.getLine))
def run (source root : System.FilePath) : IO Unit := do
  check (!(← (root/"runtime.sha256").pathExists)) "preserve earlier provider lifetime evidence"
  IO.FS.createDirAll root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identity.exitCode == 0) "runtime identity unavailable"
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let config := root/"eggshell.toml"
  IO.FS.writeFile config ("default = \"work\"\n[eggs]\nwork = \""++(source/"work.project").toString++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\n")
  let warm ← IO.Process.output {
    cmd := (← IO.appPath).toString
    args := #["egg","warm",(source/"work.project").toString]
    env := #[("EGGSHELL_CONFIG",some config.toString)]}
  IO.FS.writeFile (root/"warm.json") (Json.mkObj [("exitCode",toJson warm.exitCode.toNat),
    ("stdout",toJson warm.stdout),("stderr",toJson warm.stderr)]).compress
  let stopped ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["publication-control","shutdown"]}
  check (warm.exitCode == 0 && stopped.exitCode == 0) "provider audit warm or service shutdown failed"
  let project ← ProjectStore.openProject (source/"work.project")
  let expected ← IO.ofExcept (fromJson? ((← read (source/"frozen-readback.json")).getObjValD "sourceHeads") :
    Except String (Array PageMap.Head))
  let view ← ProjectStore.openView project ⟨project.manifest.identity,expected⟩
  let inputs ← view.sources.mapM fun original => do
    let some input ← PreparedInputs.load? original MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "source inputs not prepared")
    return input
  let some owners ← OwnerViews.load? view.sources | throw (IO.userError "owner inputs not prepared")
  let request : KeyedProtocol.Request := ⟨"Return the recorded head and tail facts for support case-79.",
    view.sources.map KeyedProtocol.Scope.ofSnapshot,4096,8192,none,some inputs,some owners⟩
  IO.FS.writeFile (root/"frozen-request.json") (toJson request).compress
  let some configured ← MiniLM.command (← Paths.installRoot) | throw (IO.userError "MiniLM unavailable")
  let command ← IO.ofExcept (KeyedSearchClient.command configured)
  let _ :: _ :: arguments := command | throw (IO.userError "invalid builtin provider command")
  let mut expectedResponse := none
  let mut rows := #[]
  -- Record the cold priming call; do not charge its initialization to one of
  -- the alternating warm arms or pretend that it did not consume resources.
  for (pair,isDirect) in #[(0,false),(1,false),(1,true),(2,true),(2,false),(3,false),(3,true)] do
    let began ← IO.monoNanosNow
    let result ← if isDirect then direct arguments request else process command request
    let elapsed := (← IO.monoNanosNow)-began
    if let .ok error := result.getObjValAs? String "error" then throw (IO.userError error)
    let response ← IO.ofExcept (fromJson? result : Except String KeyedProtocol.Response)
    let checked ← IO.ofExcept (KeyedProtocol.check view.sources response)
    KeyedProtocol.validateRelated view.sources checked
    if let some previous := expectedResponse then check (result == previous) "complete checked provider response changed"
    else expectedResponse := some result
    let label := s!"pair-{pair}-{if isDirect then "direct" else "process"}"
    IO.FS.writeFile (root/(label++".json")) result.compress
    rows := rows.push (Json.mkObj [("pair",toJson pair),("direct",toJson isDirect),
      ("elapsedNs",toJson elapsed),("ranked",toJson checked.ranked.length),
      ("related",toJson checked.related.length),("responseSha256",toJson (Sha256.hex result.compress.toUTF8))])
    IO.FS.writeFile (root/"rows.json") (toJson rows).compress
  check ((← (List.range 16).toArray.mapM project.current).map (·.head) == expected) "provider audit changed original heads"
  let report := Json.mkObj [("allPassed",toJson true),("fullResponseEqual",toJson true),
    ("sources",toJson view.sources.size),("timings",toJson rows),("originalHeadsUnchanged",toJson true),
    ("publicPreparationReused",toJson false),("scope",toJson "Same handler, per-call source restoration in both arms; not a hook/capacity measurement."),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") report.compress
  IO.println report.compress
end Eggshell.Research.ProviderLifetimeChecks
