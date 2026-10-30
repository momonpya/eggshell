import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let runtime := root / "query-cache-baseline-build"
  let data := root / "joint-relevance-data"
  let records := project / "docs/candidates/joint-relevance"
  check (!(← data.pathExists)) "preserve previous joint-relevance study"
  IO.FS.createDirAll data
  IO.FS.createDirAll records
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let config := Json.mkObj [("project",toJson project.toString),
    ("core",toJson (root / "query-cache-baseline-core").toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "joint-relevance-build").toString),("toolchain",toJson toolchain),
    ("baselineResponse",toJson (runtime / "runtime.rsp").toString),
    ("baselineMain",toJson (runtime / "Main.o").toString),
    ("objectModules",toJson (root / "query-cache-baseline-objects.json").toString),
    ("parents",toJson (#[] : Array String)),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.JointRelevanceSignal")]
  let settings := root / "joint-relevance-build.settings.json"
  IO.FS.writeFile settings config.pretty
  let python := study / "prefix/share/eggshell/minilm/fastembed-0.8.0/bin/python"
  let guard := Json.mkObj [("cwd",toJson project.toString),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString])]
  for (kind,command) in [
      ("build",#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString]),
      ("export",#[(root / "joint-relevance-build/StudyMain").toString,"export",data.toString]),
      ("score",#[python.toString,(project / "tools/research/joint_relevance_numeric.py").toString,
        (data / "model").toString,(data / "input.json").toString,(data / "scores.json").toString]),
      ("assess",#[(root / "joint-relevance-build/StudyMain").toString,"assess",data.toString])] do
    IO.FS.writeFile (root / ("joint-relevance-" ++ kind ++ ".guard.settings.json"))
      ((guard.setObjVal! "command" (toJson command)).setObjVal! "record" (toJson (records / (kind ++ ".guard.json")).toString)).pretty
  let repo := "cross-encoder/ms-marco-TinyBERT-L2-v2"
  let response ← IO.Process.output {cmd := "/usr/bin/curl",args := #["-fsSL","https://huggingface.co/api/models/" ++ repo]}
  check (response.exitCode == 0) "cannot resolve official model revision"
  let metadata ← IO.ofExcept (Json.parse response.stdout)
  let revision ← IO.ofExcept (metadata.getObjValAs? String "sha")
  check (revision.length == 40 && revision.toList.all Char.isAlphanum) "invalid official model revision"
  IO.FS.createDirAll (data / "model")
  for (remote,localName) in [("onnx/model.onnx","model.onnx"),("tokenizer.json","tokenizer.json")] do
    let fetched ← IO.Process.output {cmd := "/usr/bin/curl",args := #["-fsSL","--max-time","120",
      "https://huggingface.co/" ++ repo ++ "/resolve/" ++ revision ++ "/" ++ remote,
      "-o",(data / "model" / localName).toString]}
    check (fetched.exitCode == 0) "cannot fetch official numerical model"
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [("repo",toJson repo),("revision",toJson revision),
    ("stage",toJson "numerical signal probe only; no actual hook or adoption"),
    ("modelLanguage",toJson "English; does not establish multilingual operation"),
    ("source",toJson "fixed R40 plus sealed original supplements"),
    ("candidates",toJson "all nonempty existing canonical bounded record units, no semantic top-K"),
    ("budgetProbe",toJson "120000 original row wire characters only; optimistic, excludes all control and frames"),
    ("stop",toJson "do not build a hook if this optimistic prefix fails the existing 98 percent evidence gate; do not tune the model, K or score weights to labels"),
    ("pythonBoundary",toJson "ONNX/tokenizer inference only; export, ranking and assessment are Lean"),
    ("embeddingModelChanged",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Prepared bounded original-text joint-relevance signal experiment"
