import tools.research.OriginalEvidence

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let source := "first\nβ := \"quoted\"\nlast\n"
  let bytes := source.toUTF8
  let file : File := ⟨"source.txt",OriginalEvidence.fingerprint bytes,bytes.size⟩
  let some image := OriginalEvidence.image? file bytes | throw (IO.userError "valid reference rejected")
  let database := String.ofList (List.replicate 64 'd')
  let payload := "prefix\nβ := \"quoted\"\nsuffix\n"
  let doc : Document := {
    owner := "owner"
    work := "work"
    source := some payload
    workText := some "arbitrary tool invocation"
    native := true
    occurrences := #[⟨"session","turn","call"⟩]
    files := #[file] }
  let expected := #["β := \"quoted\""]
  let plain := OriginalEvidence.locate database doc image expected
  check (plain.size == 1 && plain.all (·.read.source.file?.isNone)) "plain output lost or became file certification"
  let encoded := (Json.mkObj [("output",toJson payload),("exitCode",toJson (0 : Nat))]).compress
  let quoted := OriginalEvidence.locate database {doc with source := some encoded} image expected
  check (quoted.size == 1) "encoded output missing or double counted"
  let some witness := quoted[0]? | throw (IO.userError "encoded witness missing")
  let read := witness.read
  let some slice := scalarSlice encoded read.binding.first read.binding.limit | throw (IO.userError "bad raw bounds")
  check ((Json.parse ("\"" ++ slice ++ "\"") >>= Json.getStr?).toOption == some (expected[0]! ++ "\n"))
    "decoded match does not name its actual escaped bytes"
  let nested := (Json.mkObj [("result",Json.mkObj [("arbitrary",toJson payload)])]).compress
  check ((OriginalEvidence.locate database {doc with source := some nested} image expected).size == 1)
    "nested arbitrary JSON field was filtered by name"
  let numbered := "  40\tβ := \"quoted\"\n"
  check ((OriginalEvidence.locate database {doc with source := some numbered} image expected).size == 1)
    "numbered evidence with unsupported command syntax lost"
  check ((OriginalEvidence.locate database {doc with files := #[]} image expected).isEmpty) "unbound source path accepted"
  check ((OriginalEvidence.locate database {doc with native := false} image expected).isEmpty) "answer text became original evidence"
  check ((OriginalEvidence.locate database {doc with source := some "β := 2\n"} image expected).isEmpty) "changed code accepted"
  check ((OriginalEvidence.image? file (source.replace "first" "FIRST").toUTF8).isNone)
    "same-size source mutation accepted"
  let block := expected.push "last"
  check ((OriginalEvidence.locate database {doc with source := some "β := \"quoted\"\nlast\n"} image block).size == 1)
    "complete multiline reference lost"
  check ((OriginalEvidence.locate database {doc with source := some "β := \"quoted\"\n"} image block).isEmpty)
    "a reference missing its last line was accepted"
  check ((OriginalEvidence.locate database doc image #[]).isEmpty) "empty reference accepted"
  check ((OriginalEvidence.locate database doc image #["   "]).isEmpty) "blank reference accepted"
  IO.println (Json.mkObj [("checks",toJson (13 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("sourceWrites",toJson (0 : Nat)),("productionAdoption",toJson false)]).compress
