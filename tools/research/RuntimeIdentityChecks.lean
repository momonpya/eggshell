import Eggshell.Numerical
open Lean Eggshell
namespace Eggshell.Research.RuntimeIdentityChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def implementation : String := Sha256.hex (toJson (MiniLM.embeddingSource,
  BlockScore.implementation,include_str "../../Eggshell/Numerical.lean",include_str "../../Eggshell/DaemonWire.lean",
  include_str "EncoderPool.lean")).compress.toUTF8
def factored (config : Numerical.Config) : String :=
  Sha256.hex (toJson (config.model,config.models.normalize.toString,config.python.normalize.toString,implementation)).compress.toUTF8
def original (config : Numerical.Config) : String :=
  Sha256.hex (toJson (config.model,config.models.normalize.toString,config.python.normalize.toString,
    MiniLM.embeddingSource,BlockScore.implementation,include_str "../../Eggshell/Numerical.lean",
    include_str "../../Eggshell/DaemonWire.lean",include_str "EncoderPool.lean")).compress.toUTF8
def measure (key : Numerical.Config → String) (count : Nat) : IO Json := do
  let vary ← IO.mkRef (0 : Nat)
  let started ← IO.monoMsNow
  let mut keys := #[]
  for _ in [:count] do
    let index ← vary.get
    let config : Numerical.Config := ⟨MiniLM.model,.mk s!"/runtime-models/scope-{index}",.mk "/runtime-python"⟩
    let result := key config
    check (result.utf8ByteSize == 64) "invalid numerical identity"
    keys := keys.push result
    vary.set (index+1)
  let elapsed := (← IO.monoMsNow)-started
  check (keys.toList.eraseDups.length == count) "identity omitted its model scope"
  return Json.mkObj [("elapsedMs",toJson elapsed),("keys",toJson keys)]
def run (mode : String) (root : System.FilePath) : IO Unit := do
  check (["parent","factored"].contains mode && !(← root.pathExists)) "fresh declared identity probe required"
  IO.FS.createDirAll root
  let first : Numerical.Config := ⟨MiniLM.model,.mk "/runtime-models/scope-0",.mk "/runtime-python"⟩
  check (first.key == (if mode == "parent" then original first else factored first)) "actual compiled key differs from its declared algorithm"
  -- Evaluate the static contract before measuring steady-state work.
  check (!implementation.isEmpty) "missing immutable implementation digest"
  let mut waves := #[]
  for _ in [:3] do
    let actual ← measure Numerical.Config.key 80
    let reference ← measure original 80
    let cached ← measure factored 80
    check ((if mode == "parent" then reference else cached).getObjValD "keys" == actual.getObjValD "keys")
      "actual identity sequence differs from its full reference"
    waves := waves.push (Json.mkObj [("actual",actual),("reference",reference),("factored",cached)])
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("mode",toJson mode),("waves",toJson waves),
    ("sourceContractBytes",toJson ((toJson (MiniLM.embeddingSource,BlockScore.implementation,
      include_str "../../Eggshell/Numerical.lean",include_str "../../Eggshell/DaemonWire.lean",
      include_str "EncoderPool.lean")).compress.utf8ByteSize)),("answeringModelCalls",toJson (0 : Nat)),
    ("wholeHookOrCapacityTest",toJson false)]).compress
def main (args : List String) : IO Unit := match args with
  | [mode,root] => run mode (.mk root)
  | _ => throw (IO.userError "parent|factored fresh-output")
end Eggshell.Research.RuntimeIdentityChecks
