import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def sha (file : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",file.toString]}
  check (result.exitCode == 0) "could not seal source file"
  return (result.stdout.splitOn " ").headD ""

def main (args : List String) : IO Unit := do
  let [parent,candidate,directory] := args |
    throw (IO.userError "OwnedPreparationComparison PARENT CANDIDATE NEW_ROOT")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new absolute comparison directory required"
  IO.FS.createDir root
  let mut cells : Array Json := #[]
  for count in [64,1024] do
    let fixture := root / s!"source-{count}"
    let made ← IO.Process.output {cmd := parent,args := #["make",fixture.toString,toString count]}
    check (made.exitCode == 0) s!"source fixture failed: {made.stdout}{made.stderr}"
    let source := fixture / "source.egg"
    let header ← IO.ofExcept (Json.parse (← IO.FS.readFile (source / "head")))
    let identity ← IO.ofExcept (header.getObjValAs? String "identity")
    let pagesFile := source / (identity ++ ".pages")
    let pages ← sha pagesFile
    let head ← sha (source / "head")
    for repetition in [:3] do
      let arms := if repetition % 2 == 0 then [("parent",parent),("candidate",candidate)]
        else [("candidate",candidate),("parent",parent)]
      for (arm,binary) in arms do
        let output := root / s!"{count}-{repetition}-{arm}"
        let actual ← IO.Process.output {
          cmd := binary
          args := #[source.toString,output.toString]
          env := #[("EGGSHELL_DATA_ROOT",some (output / "data").toString)]}
        check (actual.exitCode == 0) s!"{count}/{repetition}/{arm} failed: {actual.stdout}{actual.stderr}"
        let value ← IO.ofExcept (Json.parse (← IO.FS.readFile (output / "result.json")))
        check ((← IO.ofExcept (value.getObjValAs? Nat "owners")) == count) "wrong owner count"
        cells := cells.push (Json.mkObj [("arm",toJson arm),("repetition",toJson repetition),
          ("sourcePagesSha256",toJson pages),("sourceHeadSha256",toJson head),("result",value)])
    check ((← sha pagesFile) == pages && (← sha (source / "head")) == head)
      "benchmark altered original source"
  let result := Json.mkObj [("cells",toJson cells),("answeringModelCalls",toJson (0 : Nat)),
    ("sourceFilesUnchanged",toJson true),("tokenAdoptionEvidence",toJson false),
    ("scope",toJson "lexical and window preparation; no 80-user sustained-load claim")]
  IO.FS.writeFile (root / "report.json") (result.pretty ++ "\n")
  IO.println result.compress
