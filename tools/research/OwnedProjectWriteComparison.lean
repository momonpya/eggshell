import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def sha (file : System.FilePath) : IO String := do
  let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",file.toString]}
  check (output.exitCode == 0) "could not seal original comparison input"
  return (output.stdout.splitOn " ").headD ""

private def copy (source target : System.FilePath) : IO Unit := do
  check (!(← target.pathExists)) "preserve existing comparison destination"
  let output ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",source.toString,target.toString]}
  check (output.exitCode == 0) s!"source-only fixture clone failed: {output.stderr}"

private def sealProject (directory : System.FilePath) : IO (Array Json) := do
  let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "project")))
  let owners ← IO.ofExcept ((manifest.getObjValD "manifest").getObjValAs? (Array Json) "owners")
  check (owners.size == 16) "comparison changed the complete owner inventory"
  let mut files := #[Json.mkObj [("name",toJson "project"),("sha256",toJson (← sha (directory / "project")))]]
  for index in [:owners.size] do
    let identity ← IO.ofExcept (owners[index]!.getObjValAs? String "identity")
    check (identity.length == 64 && identity.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')))
      "invalid physical original identity"
    let folder := directory / "owners" / toString index / "source.egg"
    for name in ["head",identity ++ ".pages"] do
      files := files.push (Json.mkObj [("name",toJson s!"owners/{index}/source.egg/{name}"),
        ("sha256",toJson (← sha (folder / name)))])
  return files

def main (args : List String) : IO Unit := do
  let [parent,candidate,directory] := args |
    throw (IO.userError "OwnedProjectWriteComparison PARENT CANDIDATE NEW_ROOT")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute write comparison required"
  IO.FS.createDir root
  let mut cells : Array Json := #[]
  let mut inputs : Array Json := #[]
  for size in [5000,50000] do
    let profile := root / toString size
    IO.FS.createDir profile
    let active := profile / "active"
    let created ← IO.Process.output {cmd := parent,args := #["create-load",active.toString]}
    check (created.exitCode == 0) s!"original fixture failed: {created.stderr}"
    let source := active / "load-80.project"
    let frozen := profile / "frozen.project"
    copy source frozen
    let original ← sealProject source
    check (toJson (← sealProject frozen) == toJson original) "frozen original source differs"
    inputs := inputs.push (Json.mkObj [("outputBytes",toJson size),("originalFiles",toJson original)])
    for repetition in [:3] do
      let arms := if repetition % 2 == 0 then [("parent",parent),("candidate",candidate)]
        else [("candidate",candidate),("parent",parent)]
      for (arm,binary) in arms do
        check (toJson (← sealProject source) == toJson original) "arm did not start from the exact same original files"
        let privateData := profile / s!"private-{repetition}-{arm}"
        let output ← IO.Process.output {
          cmd := binary
          args := #["existing",active.toString,toString size]
          env := #[("EGGSHELL_DATA_ROOT",some privateData.toString)]}
        check (output.exitCode == 0) s!"write comparison failed: {size}/{repetition}/{arm}: {output.stderr}"
        let result ← IO.ofExcept (Json.parse (← IO.FS.readFile (active / "report.json")))
        cells := cells.push (Json.mkObj [("outputBytes",toJson size),("repetition",toJson repetition),
          ("arm",toJson arm),("result",result)])
        IO.FS.writeFile (root / "partial.json") ((toJson cells).pretty ++ "\n")
        -- Only this controller-created active source is reset. Its exact
        -- immutable boot copy and every completed result remain checked.
        IO.FS.removeDirAll source
        copy frozen source
    check (toJson (← sealProject frozen) == toJson original) "frozen original changed during comparison"
  let result := Json.mkObj [("parentSha256",toJson (← sha (.mk parent))),
    ("candidateSha256",toJson (← sha (.mk candidate))),("inputs",toJson inputs),
    ("cells",toJson cells),("sameStartingFilesAndLogicalPaths",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenAdoptionEvidence",toJson false)]
  IO.FS.writeFile (root / "report.json") (result.pretty ++ "\n")
  IO.println (Json.mkObj [("completed",toJson true),("cells",toJson cells.size)]).compress
