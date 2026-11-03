import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def sha (path : System.FilePath) : IO String := do
  let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (output.exitCode == 0) "cannot seal native project input"
  return (output.stdout.splitOn " ").headD ""

private def copy (source target : System.FilePath) : IO Unit := do
  check (!(← target.pathExists)) "comparison must not overwrite an existing destination"
  let result ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",source.toString,target.toString]}
  check (result.exitCode == 0) s!"native boot clone failed: {result.stderr}"

private def sourceSeal (root : System.FilePath) : IO Json := do
  let mut files := #[]
  for name in ["work.project","other.project"] do
    let project := root / name
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (project / "project")))
    let owners ← IO.ofExcept ((manifest.getObjValD "manifest").getObjValAs? (Array Json) "owners")
    check (owners.size == if name == "work.project" then 16 else 4) "complete owner inventory changed"
    files := files.push (Json.mkObj [("name",toJson (name++"/project")),("sha256",toJson (← sha (project / "project")))])
    for owner in [:owners.size] do
      let some entry := owners[owner]? | throw (IO.userError "source seal omitted an owner")
      let identity ← IO.ofExcept (entry.getObjValAs? String "identity")
      check (identity.length == 64 && identity.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')))
        "invalid native original identity"
      let relative := s!"{name}/owners/{owner}/source.egg/"
      for file in ["head",identity++".pages"] do
        files := files.push (Json.mkObj [("name",toJson (relative++file)),("sha256",toJson (← sha (root / relative / file)))])
  return toJson files

def main (args : List String) : IO Unit := do
  let [parent,candidate,pathText] := args |
    throw (IO.userError "OwnedProjectViewComparison PARENT CANDIDATE NEW_ROOT")
  let root := System.FilePath.mk pathText
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute view comparison root required"
  IO.FS.createDir root
  let mut cells : Array Json := #[]
  let mut inputs : Array Json := #[]
  for size in [5000,50000] do
    let profile := root / toString size
    IO.FS.createDir profile
    let active := profile / "active"
    let created ← IO.Process.output {cmd := parent,args := #["create-load",active.toString]}
    check (created.exitCode == 0) s!"native project creation failed: {created.stderr}"
    let original ← sourceSeal active
    let frozen := profile / "frozen"
    copy active frozen
    check ((← sourceSeal frozen) == original) "frozen boot differs from the active source"
    inputs := inputs.push (Json.mkObj [("outputBytes",toJson size),("sourceSeal",original),
      ("logicalPath",toJson active.toString)])
    let mut canonical : Option Json := none
    for repetition in [:3] do
      let arms := if repetition % 2 == 0 then [("parent",parent),("candidate",candidate)]
        else [("candidate",candidate),("parent",parent)]
      for (arm,binary) in arms do
        check ((← sourceSeal active) == original) "arm did not start from the exact same original files"
        let result ← IO.Process.output {
          cmd := binary,args := #["existing",binary,active.toString,toString size]
          env := #[("LEAN_NUM_THREADS",some "1")]}
        if result.exitCode != 0 then
          IO.FS.writeFile (root / "failure.json") ((Json.mkObj [("arm",toJson arm),("repetition",toJson repetition),
            ("outputBytes",toJson size),("exitCode",toJson result.exitCode.toNat),("stderr",toJson result.stderr)]).pretty ++ "\n")
          throw (IO.userError s!"native view comparison failed: {size}/{repetition}/{arm}: {result.stderr}")
        let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (active / "report.json")))
        let originals := report.getObjValD "originals"
        check (originals == report.getObjValD "freshProcess" && originals.getObjValD "observations" == toJson (320 : Nat))
          "native view comparison lost acknowledged originals"
        match canonical with
        | none => canonical := some originals
        | some expected => check (originals == expected) "candidate changed canonical original bytes, timing or work graph"
        let rounds ← IO.ofExcept (report.getObjValAs? (Array Json) "rounds")
        check (report.getObjValD "concurrentQueries" == toJson (16 : Nat)) "comparison changed its offered query count"
        let compactRounds := rounds.map fun round => Json.mkObj [("round",round.getObjValD "round"),
          ("acks",round.getObjValD "acks"),("elapsedMs",round.getObjValD "elapsedMs"),
          ("loadWindowMs",round.getObjValD "loadWindowMs"),("querySamples",round.getObjValD "querySamples"),
          ("latenciesMs",round.getObjValD "latenciesMs")]
        cells := cells.push (Json.mkObj [("arm",toJson arm),("repetition",toJson repetition),
          ("outputBytes",toJson size),("rounds",toJson compactRounds),("originals",originals),
          ("stats",report.getObjValD "stats"),("concurrentQueries",report.getObjValD "concurrentQueries"),
          ("allNativeBrokerChecksPassed",toJson true)])
        IO.FS.writeFile (root / "partial.json") ((toJson cells).pretty ++ "\n")
        IO.println (Json.mkObj [("completedCells",toJson cells.size),("arm",toJson arm),
          ("outputBytes",toJson size),("repetition",toJson repetition)]).compress
        -- These are only controller-created native fixtures. Reclaim each
        -- completed DB/cache immediately, then restore the exact same boot.
        IO.FS.removeDirAll active
        copy frozen active
    check ((← sourceSeal frozen) == original) "comparison changed its frozen boot"
  let report := Json.mkObj [("parentSha256",toJson (← sha (.mk parent))),
    ("candidateSha256",toJson (← sha (.mk candidate))),("inputs",toJson inputs),("cells",toJson cells),
    ("sameStartingFilesAndLogicalPaths",toJson true),("sameCanonicalOriginalsAndGraph",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenAdoptionEvidence",toJson false)]
  IO.FS.writeFile (root / "report.json") (report.pretty ++ "\n")
  IO.println (Json.mkObj [("completed",toJson true),("cells",toJson cells.size)]).compress
