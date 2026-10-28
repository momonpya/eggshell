import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let core := "/Users/ovm/.codex/experiments/eggshell/bounded-source-replies-20261028/scope-hook-checkout"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let library := System.FilePath.mk core / ".lake/build/lib/lean"
  if (← library.pathExists) then
    if (← library.symlinkMetadata).type == .symlink then IO.FS.removeFile library
  IO.FS.createDirAll library
  IO.FS.writeFile (root / "controller/empty-objects.json") "{}"
  let object := (root / "controller/storage-sync.o").toString
  let result ← IO.Process.output {cmd := "/usr/bin/cc",args := #["-c","-O2","-I",toolchain ++ "/include","-o",object,core ++ "/Eggshell/Storage/sync.c"]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  IO.FS.writeFile (root / "controller/base.rsp") ((toJson object).compress ++ "\n")
  let settings := Json.mkObj [
    ("project",toJson project),("core",toJson core),("output",toJson (root / "controller-build").toString),
    ("toolchain",toJson toolchain),("baselineResponse",toJson (root / "controller/base.rsp").toString),
    ("baselineMain",toJson "absent"),("baselineCore",Json.null),
    ("objectModules",toJson (root / "controller/empty-objects.json").toString),
    ("parents",toJson (#[] : Array String)),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.StudyMain")]
  IO.FS.writeFile (root / "controller-build.settings.json") settings.pretty
  IO.FS.writeFile (root / "controller-build.guard-settings.json") (Json.mkObj [
    ("record",toJson (root / "controller-build.guard.json").toString),("cwd",toJson project),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[root.toString]),("command",toJson #[toolchain ++ "/bin/lean","--run",project ++ "/tools/research/StudyBuildMain.lean",(root / "controller-build.settings.json").toString])]).pretty
