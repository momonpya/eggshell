import Eggshell.ContentCapture
import Eggshell.ContentMetadata
import Eggshell.SynapseUsage
open Lean Eggshell ContentCapture ContentCorrespondence

private def check (valid : Bool) (reason : String) : IO Unit :=
  unless valid do throw (IO.userError reason)

private def reference (inputs : Inputs) (rows : Array Output) : IO Json := do
  let some index := ContentCorrespondence.prepare? inputs | throw (IO.userError "independent full index incomplete")
  let trie := Trie.prepare rows
  let mut state := trie.start
  for source in [:inputs.size] do
    let some lines := inputs[source]? | throw (IO.userError "reference input missing")
    for row in [:lines.size] do
      let some text := lines[row]? | throw (IO.userError "reference line missing")
      state := trie.observe state (source,row+1) text
  check (state.size == trie.nodes.size) "input scan grew the output index"
  let mut checked := 0
  for node in [:trie.nodes.size] do
    let some text := trie.key? node | continue
    let positions := (ContentCorrespondence.bucket index.buckets text).toList
    let expected := match positions with
      | [] => Candidate.absent
      | [(source,row)] => .one (source,row+1)
      | _ => .ambiguous
    check (state[node]? == some expected) "suffix index differs from complete literal reference"
    checked := checked+1
  return Json.mkObj [("referenceNodes",toJson checked),("stateEntries",toJson state.size),
    ("allCandidatesExact",toJson true),("inputRows",toJson (inputs.foldl (fun n rows => n+rows.size) 0))]

private def codes (raw : String) (captured : Captured) : IO (Array String) := do
  let characters := raw.toList.toArray
  captured.aliases.mapM fun entry => do
    let some code := code? characters entry | throw (IO.userError "saved alias lost its literal original bytes")
    return code

private def capture (workspace : System.FilePath) (input : Json) (raw : String) : IO (Captured × Nat) := do
  let before ← IO.monoMsNow
  let acquired ← captureInputs workspace input none (before+10000)
  check acquired.record.valid "generic file hints did not capture actual input"
  check (!acquired.record.closed) "file hint acquired closed execution authority"
  let result ← finish workspace acquired raw ((← IO.monoMsNow)+10000)
  check result.complete "stable original inputs did not reach sealed EOF"
  return (result,(← IO.monoMsNow)-before)

private def presentation (raw : String) (captured : Captured) : IO Nat := do
  let occurrence : Synapses.Occurrence := ⟨"capture-session","capture-turn","capture-use"⟩
  let doc : Synapses.Extraction.Document := {
    owner := "v1",work := "v2",workText := none,source := some raw
    native := true,occurrences := #[occurrence],files := #[]}
  let catalog ← IO.ofExcept (ContentMetadata.catalog (Sha256.hex "database".toUTF8) doc captured)
  let reads := catalog.located.map (·.read)
  let mut count := 0
  for located in catalog.located do
    let read := located.read
    let some file := read.source.file? | throw (IO.userError "alias fixture lacks file")
    let packet := fun file owner work occurrence code =>
      let origin := (read.binding.database,owner,work,occurrence)
      "EGGSHELL SHARED SOURCE DATA\nOriginal recorded file data; advisory, not a completed operation.\nSOURCE " ++
        (toJson (file : Synapses.File)).compress ++ "\nORIGINAL READS " ++
        (toJson #[(toJson origin).compress]).compress ++ "\nCODE\n" ++
        toString read.source.first ++ "\t" ++ code ++ "\nEND SOURCE\nEND EGGSHELL SHARED SOURCE DATA\n"
    let valid := packet file doc.owner doc.work occurrence located.text
    let found := Synapses.Extraction.presented valid #[doc] reads
    check (found.ranges.contains read.source && found.coversBinding read.binding)
      "literal or escaped original code was labelled undelivered"
    for invalid in #[
        packet file doc.owner doc.work occurrence (located.text ++ " changed"),
        packet {file with fingerprint := Sha256.hex "different".toUTF8} doc.owner doc.work occurrence located.text,
        packet file "v999" doc.work occurrence located.text,
        packet file doc.owner "v999" occurrence located.text,
        packet file doc.owner doc.work {occurrence with useId := "other"} located.text,
        "SAVED SOURCE POSITIONS\n" ++ (toJson read.source).compress ++ "\nEND SAVED SOURCE POSITIONS\n"] do
      check ((Synapses.Extraction.presented invalid #[doc] reads).ranges.isEmpty)
        "unbound code or location-only notice acquired a delivered label"
      count := count+1
  return count

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "ContentCaptureAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "keep earlier capture trial"
    IO.FS.createDir root
    let code := "alpha_token();\n}\n  警告(\"é🧠\");\n}\nomega_tail();\n"
    IO.FS.writeFile (root / "source.cpp") code
    let pureReference ← reference #[(code.splitOn "\n").dropLast.toArray]
      (outputs "path:1:alpha_token();\nother prefix  警告(\"é🧠\");\n}\n")
    let largeReference ← reference #[(Array.range 10000).map fun row => s!"input_{row}();"]
      (outputs "one:input_500();\ntwo:input_9999();\nmissing();\n")
    let mut reports := #[]
    for command in #["cat source.cpp","nl -ba source.cpp",
        "awk '{print FILENAME \":\" NR \":\" $0}' source.cpp"] do
      let input := Json.mkObj [("arbitrary_provider_argument",toJson command)]
      let observed ← IO.Process.output {cmd := "/bin/sh",args := #["-c",command],cwd := root.toString}
      check (observed.exitCode == 0) "actual native read failed"
      let (captured,elapsed) ← capture root input observed.stdout
      let actual ← codes observed.stdout captured
      check (actual.contains "alpha_token();" && actual.contains "  警告(\"é🧠\");" && actual.contains "omega_tail();")
        "a literal source line was lost because of its output prefix"
      check (!actual.contains "}") "ambiguous repeated input line became a unique coordinate"
      reports := reports.push (Json.mkObj [("command",toJson command),("aliases",toJson captured.aliases.size),
        ("elapsedMs",toJson elapsed),("originalCodeEqual",toJson true)])
    let arbitrary := Json.mkObj [("arguments",toJson #["nonstandard_reader","source.cpp"])]
    let strict ← SourceEvidence.capture root arbitrary ((← IO.monoMsNow)+10000)
    check (!strict.record.valid) "fixture unexpectedly used the recognized-command path"
    let raw := (Json.mkObj [("unrelated_mcp_payload",toJson ("prefix:" ++ code)),("opaque",toJson "retained")]).compress
    let (structured,jsonMs) ← capture root arbitrary raw
    let structuredCodes ← codes raw structured
    check (structuredCodes.contains "alpha_token();" && structuredCodes.contains "  警告(\"é🧠\");")
      "escaped structured provider output lost original scalar coordinates"
    let mutationChecks ← presentation raw structured
    let acquired ← captureInputs root arbitrary none ((← IO.monoMsNow)+10000)
    IO.FS.writeFile (root / "source.cpp") (code.replace "alpha_token" "other_token")
    let changed ← finish root acquired code ((← IO.monoMsNow)+10000)
    check (!changed.complete && changed.aliases.isEmpty) "changed input acquired historical coordinates"
    IO.FS.writeFile (root / "source.cpp") code
    let expired ← finish root acquired code (← IO.monoMsNow)
    check (!expired.complete && expired.aliases.isEmpty) "unfinished scan asserted uniqueness"
    IO.FS.writeFile (root / "other.cpp") "alpha_token();\n"
    let both := Json.mkObj [("arguments",toJson #["source.cpp","other.cpp"])]
    let (multiple,_) ← capture root both "alpha_token();\nomega_tail();\n"
    let multipleCodes ← codes "alpha_token();\nomega_tail();\n" multiple
    check (!multipleCodes.contains "alpha_token();" && multipleCodes.contains "omega_tail();")
      "one input file hid an ambiguous match in another input"
    let long := String.ofList (List.replicate (2*1024*1024) 'x') ++ "\nalpha_token();\n"
    IO.FS.writeFile (root / "long.cpp") long
    let (bounded,longMs) ← capture root (Json.mkObj [("path",toJson "long.cpp")]) "prefix:alpha_token();\n"
    check ((← codes "prefix:alpha_token();\n" bounded).contains "alpha_token();")
      "discarding an irrelevant long input row lost a later match"
    let report := Json.mkObj [("cases",toJson reports),("reference",pureReference),("largeReference",largeReference),
      ("jsonElapsedMs",toJson jsonMs),("longInputElapsedMs",toJson longMs),
      ("changedInputRejected",toJson true),("unfinishedInputRejected",toJson true),
      ("crossFileAmbiguityRetained",toJson true),("noCommandClassifier",toJson true),
      ("presentationMutationChecks",toJson mutationChecks),
      ("atomicPublicationMeasured",toJson false),("actualHookMeasured",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]
    IO.FS.writeFile (root / "results.json") report.pretty
    IO.println report.compress
    return 0
  catch error => IO.eprintln error.toString; return 1
