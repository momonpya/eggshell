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
  schedule "local-judgment-download"
def prepareDownload : IO Unit := do
  idle
  let stopped ← read (base/"local-judgment-download.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    !(← (root/"runtime.tar.gz").pathExists) && !(← (root/"model.gguf").pathExists)) "previous download still owns work or bytes"
  write (records/"metadata-refusal.json") (Json.mkObj [("guard",stopped),
    ("error",toJson "the metadata child lacked explicit LEAN_PATH; no network request or model started")])
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
end LocalJudgmentStudy
def main : List String → IO Unit
  | ["prepare"] => LocalJudgmentStudy.prepare
  | ["download"] => LocalJudgmentStudy.download
  | ["prepare-download"] => LocalJudgmentStudy.prepareDownload
  | _ => throw (IO.userError "LocalJudgmentStudy prepare|download")
