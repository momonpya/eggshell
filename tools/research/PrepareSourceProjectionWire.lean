import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (text needle replacement : String) : IO String := do
  check ((text.splitOn needle).length == 2) "source projection anchor is absent or ambiguous"
  return text.replace needle replacement

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let original := root / "query-cache-baseline-core"
  let core := root / "source-projection-wire-core"
  let resumed ← core.pathExists
  if resumed then
    check (!(← (root / "source-projection-wire-runtime-build").pathExists)) "preserve already compiled source projection candidate"
    check ((← IO.FS.readFile (core / "Eggshell/Handoff.lean")) ==
      (← IO.FS.readFile (original / "Eggshell/Handoff.lean"))) "unsealed source changed evidence selection"
    check ((← IO.FS.readFile (core / "Eggshell/PublicationWire.lean")) ==
      (← IO.FS.readFile (original / "Eggshell/PublicationWire.lean"))) "preserve sealed source projection candidate"
  else
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",original.toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate projection candidate"
  for name in ["Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean"] do
    let source ← IO.FS.readFile (original / name)
    let source ← once source "public import Eggshell.CanonicalSourcePrepared\n"
      "public import Eggshell.CanonicalSourcePrepared\npublic import tools.research.SourceProjectionWire\n"
    let source ← if name.endsWith "PublicationClient.lean" then
      once source
        "  let result ← IO.ofExcept (Json.parse response >>= fromJson? (α := Synapses.CanonicalSource.Shared.Projection))"
        ("  let wire ← IO.ofExcept (Json.parse response >>= fromJson? (α := Eggshell.Research.SourceProjectionWire.Wire))\n" ++
         "  let some result := Eggshell.Research.SourceProjectionWire.unpack wire |\n" ++
         "    throw (IO.userError \"prepared source projection has an invalid dictionary reference\")")
    else do
      once source
        "      prepared.map (fun (owner,recipe) => (owner,recipe.records))⟩\n    return toJson result"
        "      prepared.map (fun (owner,recipe) => (owner,recipe.records))⟩\n    return toJson (Eggshell.Research.SourceProjectionWire.pack result)"
    IO.FS.writeFile (core / name) source
  let moduleFile := "tools/research/SourceProjectionWire.lean"
  IO.FS.createDirAll (core / moduleFile).parent.get!
  IO.FS.writeFile (core / moduleFile) (← IO.FS.readFile (project / moduleFile))
  let stamp ← IO.FS.readFile (original / "Eggshell/PublicationWire.lean")
  let stamp ← once stamp "  (include_str \"PublicationWire.lean\").toUTF8,"
    "  (include_str \"../tools/research/SourceProjectionWire.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,"
  IO.FS.writeFile (core / "Eggshell/PublicationWire.lean") stamp
  check ((← IO.FS.readFile (core / "Eggshell/Handoff.lean")) ==
    (← IO.FS.readFile (original / "Eggshell/Handoff.lean"))) "projection changed evidence selection"
  IO.FS.writeFile (project / "docs/candidates/source-projection-wire/preparation.json")
    (Json.mkObj [("resumedUnsealedOwnedSource",toJson resumed),("handoffSourceBytesUnchanged",toJson true),
      ("previousCloneRemovalPerformed",toJson false),("adopted",toJson false)]).pretty
  IO.println "Isolated exact source projection wire; preserved owner/row/recipe validation and Handoff bytes"
