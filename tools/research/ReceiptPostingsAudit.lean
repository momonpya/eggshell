import tools.research.ReceiptBefore
import Eggshell.Sha256
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms Eggshell.SpanPostings.directory_exact
#print axioms Eggshell.SpanPostings.Index.lookup_exact

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

private def project (witnesses : Array (SharedWitness reads)) : Array (Read × File × Nat × String) :=
  witnesses.map fun witness => (witness.row,witness.file,witness.number,witness.code)

private def scenario (population : Nat) : IO Json := do
  let text := String.join ((List.range population).map fun number => s!"  {number+1}\tSYMBOL_{number+1}\n")
  let raw := (Json.mkObj [("output",toJson text)]).compress
  let decoded ← IO.ofExcept (layout raw)
  let occurrence : Occurrence := ⟨"receipt-fixture","turn","read"⟩
  let file : File := ⟨"source.cpp",Sha256.hex text.toUTF8,text.utf8ByteSize⟩
  let doc : Document := {
    owner := "owner",work := "work",workText := none,source := some raw
    native := true,occurrences := #[occurrence],files := #[file]}
  let mut rows : Array Read := #[]
  for line in textLines decoded.text do
    let some (number,_) := numbered line.text | continue
    rows := rows.push ⟨occurrence,⟨file,number,number⟩,
      ⟨"database",doc.owner,doc.work,decoded.offsets[line.first]!,decoded.offsets[line.limit]!⟩,#[]⟩
  check (rows.size == population) "legacy fixture did not decode every original numbered line"
  let some first := rows[0]? | throw (IO.userError "empty legacy fixture")
  let reads := rows ++ #[first,first,{first with binding := {first.binding with work := "other-work"}},
    {first with source := ⟨({file with fingerprint := Sha256.hex "other".toUTF8} : File),1,1⟩},
    {first with occurrence := {occurrence with useId := "other"}},
    {first with source := ⟨file,population+1,population+1⟩}]
  let origin := ("database",doc.owner,doc.work,occurrence)
  let code := String.join ((List.range population).map fun number => s!"{number+1}\tSYMBOL_{number+1}\n")
  let body := "EGGSHELL SHARED SOURCE DATA\nOriginal recorded file data; advisory, not a completed operation.\nSOURCE " ++
    (toJson file).compress ++ "\nORIGINAL READS " ++ (toJson #[(toJson origin).compress]).compress ++
    "\nCODE\n" ++ code ++ "END SOURCE\nEND EGGSHELL SHARED SOURCE DATA\n"
  let before ← IO.monoMsNow
  let reference := Research.ReceiptBefore.sharedPresented body #[doc] reads
  let _ ← IO.ofExcept (if reference.size == population+2 then Except.ok () else .error "reference fixture lost duplicate witnesses")
  let referenceMs := (← IO.monoMsNow)-before
  let started ← IO.monoMsNow
  let indexed := sharedPresented body #[doc] reads
  check (project indexed == project reference) "span postings changed witness values, multiplicity or order"
  let indexedMs := (← IO.monoMsNow)-started
  for invalid in #[body.replace "SYMBOL_1\n" "ALTERED_1\n",body.replace "ORIGINAL READS " "NO ORIGIN "] do
    let old := Research.ReceiptBefore.sharedPresented invalid #[doc] reads
    let current := sharedPresented invalid #[doc] reads
    check (project old == project current) "invalid frame diverged from reference validation"
  return Json.mkObj [("population",toJson population),("readCandidates",toJson reads.size),
    ("referenceMs",toJson referenceMs),("indexedMs",toJson indexedMs),
    ("witnesses",toJson indexed.size),("exactOrderedWitnesses",toJson true),
    ("duplicatesRetained",toJson true),("invalidMetadataPreserved",toJson true)]

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "ReceiptPostingsAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "new receipt directory required"
    IO.FS.createDir root
    let mut results := #[]
    for population in [32,256,1024] do
      let result ← scenario population
      results := results.push result
      IO.println result.compress
    IO.FS.writeFile (root / "results.json") (Json.mkObj [("scenarios",toJson results),
      ("synthetic",toJson true),("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
    return 0
  catch error => IO.eprintln error.toString; return 1
