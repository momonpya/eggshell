import tools.research.StudyLocal
open Lean StudyLocal
def study := project/"docs/candidates/located-lexical-input"
def sourceRoot := base/"current-six/located-runtime-source"
def buildRoot := base/"current-six/located-runtime-build"

def replaceOnce (path : System.FilePath) (before after : String) : IO Unit := do
  let text ← IO.FS.readFile path
  check ((text.splitOn before).length == 2) ("one exact source site required: "++path.toString)
  IO.FS.writeFile path (text.replace before after)

def main (args : List String) : IO Unit := do
  if args == ["build"] then
    idle
    let parentBuild := base/"owned-selection-runtime-build"
    check ((← hash (parentBuild/"StudyMain")) == "36612afeda566b5bb93cdfaaaa1d2f766b5a2dfe4e45df86c5757b057aa9ecab") "fixed runtime parent changed"
    materialize parentBuild sourceRoot buildRoot "tools.research.OwnedSelectionRuntime" "current-six-located-runtime-settings.json"
    replaceOnce (sourceRoot/"tools/RetrievalIndex.lean")
      "def open? (source : Snapshot) : IO (Option (Reader source)) := do"
      "def openLocated? (source : Snapshot) : IO (Option (DB.Sidecar.Storage × Reader source)) := do"
    replaceOnce (sourceRoot/"tools/RetrievalIndex.lean")
      "      return some ⟨index, expected⟩\n    catch _ => pure ()\n  pure none\n"
      "      return some (storage,⟨index, expected⟩)\n    catch _ => pure ()\n  pure none\n\n/-- Preserve the existing lookup and its order while allowing consumers to\nretain the actual storage of an already prepared immutable root. -/\ndef open? (source : Snapshot) : IO (Option (Reader source)) := do\n  return (← openLocated? source).map Prod.snd\n"
    let inputs := sourceRoot/"Eggshell/PreparedInputs.lean"
    replaceOnce inputs
      "  let lexicalPath ← RetrievalResearch.Index.path source storage\n  let workspace ← PageMap.pin lexicalPath\n  let some lexical ← PreparedRoot.select? source workspace |\n    throw (IO.userError \"lexical input is not prepared\")\n  let expected ← RetrievalResearch.Index.stamp source\n"
      "  let some locatedLexical ← RetrievalResearch.Index.openLocated? source |\n    throw (IO.userError \"lexical input is not prepared\")\n  let lexical := locatedLexical.2.index\n  let expected := locatedLexical.2.expected\n"
    replaceOnce inputs "lexical := some ⟨storage,lexical.head⟩,numeric := numerical"
      "lexical := some (Root.fromLexical locatedLexical),numeric := numerical"
    let marker := "structure Root where\n  storage : Sidecar.Storage\n  head : PageMap.Head\n  deriving BEq,ToJson,FromJson\n"
    replaceOnce inputs marker (marker++"\n/-- The location belongs to the reader actually selected, independently of\nthe requested cache lane. Keeping it prevents nonexistent private lookups. -/\ndef Root.fromLexical {source : Snapshot} (located : Sidecar.Storage × RetrievalResearch.Index.Reader source) : Root :=\n  ⟨located.1,located.2.index.head⟩\n\ntheorem Root.fromLexical_location {source : Snapshot}\n    (located : Sidecar.Storage × RetrievalResearch.Index.Reader source) :\n    (Root.fromLexical located).storage = located.1 ∧\n    (Root.fromLexical located).head = located.2.index.head := ⟨rfl,rfl⟩\n")
    IO.FS.createDirAll study
    let mut patch := ""
    for relative in ["tools/RetrievalIndex.lean","Eggshell/PreparedInputs.lean"] do
      let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/"++relative,"-L","b/"++relative,
        (base/"owned-selection-runtime-source"/relative).toString,(sourceRoot/relative).toString]}
      check (result.exitCode == 1) "candidate must contain exactly the intended source difference"
      patch := patch++result.stdout
    IO.FS.writeFile (study/"implementation.patch") patch
    write (study/"plan.json") (Json.mkObj [
      ("parentSha256",toJson "36612afeda566b5bb93cdfaaaa1d2f766b5a2dfe4e45df86c5757b057aa9ecab"),
      ("cause",toJson "lexical warm reuses an existing database index but prepared-input capture pins the requested private path"),
      ("change",toJson "carry the verified reader's actual storage and head; preserve lookup order, postings, scoring, graph and selection"),
      ("proofBoundary",toJson "pure location/head transport is proved; filesystem behavior and delivery require native tests"),
      ("newCacheCopy",toJson false),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("newSeedRequiredBeforeModelComparison",toJson true)])
    guard "current-six-located-runtime-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"current-six-located-runtime-settings.json").toString]
  else if args == ["audit"] then
    discard <| finished "current-six-located-runtime-build"
    guard "current-six-located-runtime-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/LocatedLexicalStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let invoke := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| invoke #["inspect",buildRoot.toString,(study/"native.json").toString]
    discard <| invoke #["compare-sources",(base/"owned-selection-runtime-build").toString,buildRoot.toString,
      (study/"sources.json").toString,"tools.RetrievalIndex","Eggshell.PreparedInputs"]
    IO.FS.writeFile (study/"axioms.lean")
      "import Eggshell.PreparedInputs\n#print axioms Eggshell.PreparedInputs.Root.fromLexical_location\n"
    let output ← command "/usr/bin/env" #["LEAN_PATH="++(buildRoot/"lib").toString,(compiler/"bin/lean").toString,
      "-j1","-M1536",(study/"axioms.lean").toString]
    IO.FS.writeFile (study/"axioms.txt") output
  else throw (IO.userError "build/audit required")
