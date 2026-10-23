import Eggshell.SynapseUsage

open Lean Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def file : File := ⟨"src/日本語.cpp", String.ofList (List.replicate 64 'a'), 100⟩
private def query : String := String.ofList (List.replicate 64 'b')
private def occurrence (name : String) : Occurrence := ⟨"session", "turn", name⟩
private def command := "nl -ba src/日本語.cpp | sed -n '10,12p'"
private def output := "    10\t日本語 α\n    11\tbeta\n    12\tgamma\n"

private def doc : Document := {
  owner := "observation", work := "work", workText := some ("shell\n" ++
    (Json.mkObj [("command", toJson command)]).compress)
  source := some (toJson output).compress
  native := true, occurrences := #[occurrence "read"], files := #[file] }

private def checkSource : IO (Array Read × Presentation) := do
  let trace : Trace := {}
  let trace ← IO.ofExcept (trace.start (occurrence "read") 0 command)
  let trace ← IO.ofExcept (trace.finish (occurrence "read") 1 output)
  let reads ← IO.ofExcept (locateReads "database" doc trace)
  let some firstRead := reads[0]? | throw (IO.userError "no located read")
  check (reads.size == 1 && firstRead.read.source.first == 10 &&
    firstRead.read.source.last == 12) "contiguous read did not retain its original rows"
  let rows ← IO.ofExcept (recordedRows "database" doc)
  check (rows.size == 3) "stored scalar rows missing"
  let first := rows[0]!
  let packet := "\nWORK GRAPH observation\n  GROUNDED OUTCOME\n  ORIGINAL CHARS [" ++
    toString first.binding.first ++ "," ++ toString first.binding.limit ++
    ") decoded\n  DECODED JSON STRING DATA\n    10\t日本語 α\n  TRACE\n"
  let presented := presented packet #[doc] rows
  check (presented.ranges == #[first.source] && presented.uncertain.isEmpty)
    "Unicode or JSON escape coordinates changed during delivery verification"
  let bad := Extraction.presented (packet.replace "日本語 α" "wrong text") #[doc] rows
  check (bad.uncertain.contains file && bad.ranges.isEmpty) "tampered packet became missing evidence"
  let some range := citation "日本語.cpp:10–12" "src/%E6%97%A5%E6%9C%AC%E8%AA%9E.cpp:10" #[file] |
    throw (IO.userError "citation missing")
  check (range.first == 10 && range.last == 12) "citation end line lost"
  check ((citation "日本語.cpp:10–12" "src/日本語.cpp:11" #[file]).isNone) "conflicting citation admitted"
  let answer := {doc with
    owner := "answer"
    native := false
    source := some "[日本語.cpp:11](src/日本語.cpp:11)"}
  let supported ← IO.ofExcept (addAnswer "database" answer reads Graph.empty)
  let supports := supported.snapshot.filterMap fun fact =>
    match fact with | .supports value => some value | _ => none
  let some precise := supports[0]? | throw (IO.userError "single-line support missing")
  check (precise.binding.first == rows[1]!.binding.first &&
    precise.binding.limit == rows[1]!.binding.limit)
    "citation retained the whole ancestor read instead of its exact original row"
  return (rows, presented)

private def checkElidedReads : IO Unit := do
  for delimiter in ["…","..."] do
    for unit in ["tokens","chars","bytes","lines"] do
      for count in [1,12,2486,1000000] do
        let marker := delimiter ++ toString count ++ " " ++ unit ++ " truncated" ++ delimiter
        for body in [marker ++ "tail","prefix" ++ marker ++ "tail","prefix" ++ marker] do
          check ((numbered ("    11\t" ++ body)).isNone) "elided fragments became one original source row"
  check (numbered "    11\t// tokens truncated" == some (11,"// tokens truncated") &&
    numbered "    11\treturn x…y;" == some (11,"return x…y;"))
    "ordinary code containing words or ellipsis was discarded"
  let elided := "    10\t日本語 α\n    11\tleft…2486 tokens truncated…unrelated tail\n    12\tgamma\n"
  for raw in [elided,(toJson elided).compress,(Json.mkObj [("output",toJson elided)]).compress] do
    let damaged := {doc with source := some raw}
    let rows ← IO.ofExcept (recordedRows "database" damaged)
    check (rows.map (·.source.first) == #[10,12]) "elision lost intact neighbours or invented the missing row"
    let reads ← IO.ofExcept (recordedReads "database" damaged)
    check (reads.size == 2 && reads.all (fun row => row.read.source.first == row.read.source.last))
      "a source range crossed the elision gap"
    let trace : Trace := {}
    let trace ← IO.ofExcept (trace.start (occurrence "read") 0 command)
    let trace ← IO.ofExcept (trace.finish (occurrence "read") 1 elided)
    let located ← IO.ofExcept (locateReads "database" damaged trace)
    check (located.size == 2 && located.all (fun row => row.read.source.first != 11))
      "native derivation attached an original row to an elided display"

private def checkFeedback (rows : Array Read) (packet : Presentation) : IO Unit := do
  let requested := #[rows[0]!.source]
  let feedback : Feedback := {}
  let feedback := feedback.start (occurrence "before-packet")
  let feedback := feedback.present packet
  let feedback ← IO.ofExcept (feedback.completedRead (occurrence "before-packet") query requested requested)
  check ((feedback.graph.usageCounts requested[0]!).omittedThenRead == 1)
    "later pre-tool context retroactively removed an earlier omission"
  let feedback := feedback.start (occurrence "after-packet")
  let feedback ← IO.ofExcept (feedback.completedRead (occurrence "after-packet") query requested requested)
  check ((feedback.graph.usageCounts requested[0]!).reread == 1)
    "ordinary reread rewarded as an omission"
  let uncertain := feedback.present {uncertain := ({} : Std.HashSet File).insert file}
  let uncertain := uncertain.start (occurrence "uncertain")
  let uncertain ← IO.ofExcept (uncertain.completedRead (occurrence "uncertain") query requested requested)
  check ((uncertain.graph.usageCounts requested[0]!).omittedThenRead == 1)
    "unknown delivery was labelled missing"
  let cited ← IO.ofExcept (feedback.answer (occurrence "answer") query
    "[日本語.cpp:10](src/日本語.cpp:10)")
  check ((cited.graph.usageCounts requested[0]!).deliveredThenCited == 1) "delivered citation not recorded"

private def checkTrace : IO Unit := do
  let trace : Trace := {}
  let trace ← IO.ofExcept (trace.start (occurrence "A") 0 "search")
  let trace ← IO.ofExcept (trace.start (occurrence "B") 1 "src/a.cpp:10")
  let trace ← IO.ofExcept (trace.finish (occurrence "A") 2 "src/a.cpp:10")
  let trace ← IO.ofExcept (trace.finish (occurrence "B") 3 "done")
  check (trace.graph.evidenceCount == 0) "parallel call consumed a future output"
  let trace ← IO.ofExcept (trace.start (occurrence "C") 4 "src/a.cpp:10")
  let trace ← IO.ofExcept (trace.finish (occurrence "C") 5 "done")
  check (trace.graph.evidenceCount == 2) "finished path and path-line witnesses were lost"
  let duplicate ← IO.ofExcept (trace.finish (occurrence "C") 6 "done")
  check (duplicate.graph.snapshot == trace.graph.snapshot) "duplicate notification increased weight"

private def checkRepeatedPositions : IO Unit := do
  let text := "    10\t前😀 NEEDED_SYMBOL\n    11\tother\n    12\tNEEDED_SYMBOL\n"
  let trace : Trace := {}
  let trace ← IO.ofExcept (trace.start (occurrence "producer") 10 command)
  let trace ← IO.ofExcept (trace.finish (occurrence "producer") 20 text)
  let trace ← IO.ofExcept (trace.start (occurrence "consumer") 30 "NEEDED_SYMBOL NEEDED_SYMBOL")
  let some started := trace.starts[occurrence "consumer"]? | throw (IO.userError "missing started consumer")
  check (started.pending.size == 2 && started.pending.all (fun pending =>
    literal pending.input pending.edge.inputFirst pending.edge.inputLimit pending.edge.term &&
    literal pending.output pending.edge.outputFirst pending.edge.outputLimit pending.edge.term))
    "repeated producer positions were lost or duplicate arguments multiplied evidence"
  let original := {doc with source := some (toJson text).compress, occurrences := #[occurrence "producer"]}
  let trace ← IO.ofExcept (trace.finish (occurrence "consumer") 40 "done")
  let reads ← IO.ofExcept (locateReads "database" original trace)
  let trace ← IO.ofExcept (trace.locate (({} : Std.HashMap Occurrence (Array OutputRow)).insert
    (occurrence "producer") (reads.flatMap (·.rows))))
  let consumed := trace.graph.snapshot.filterMap fun fact => match fact with
    | .consumed edge => some edge | _ => none
  check (consumed.size == 2 && consumed.any (·.rows.any (·.first == 10)) &&
    consumed.any (·.rows.any (·.first == 12))) "later original row disappeared behind the first token"
  let repeated ← IO.ofExcept (trace.finish (occurrence "consumer") 50 "done")
  check (repeated.graph.snapshot == trace.graph.snapshot) "repeated completion added token positions again"
  let some pending := started.pending[0]? | throw (IO.userError "missing pending literal witness")
  check ((Pending.check? {pending.edge with outputFirst := pending.edge.outputFirst+1}
    pending.input pending.output).isNone) "shifted output span passed its literal certificate"
  check ((Pending.check? {pending.edge with term := "OTHER_SYMBOL"}
    pending.input pending.output).isNone) "different literal word passed its certificate"

private def checkKinds : IO Unit := do
  for word in ["1", "180", "１２３", "١٢٣", "//", "/", "-", "--flag", "12p"] do
    check ((termKind? word).isNone) s!"non-name became an independent witness: {word}"
  for word in ["X", "_x", "TargetTriple", "clang::driver", "日本語", "한국어", "каталог", "café", "école"] do
    check (termKind? word == some .identifier) s!"named Unicode identifier disappeared: {word}"
  check (termKind? "/123" == some .path && termKind? "src/日本語.cpp:10" == some .pathLine)
    "named/numeric file components or explicit path-line witnesses disappeared"
  let trace : Trace := {}
  let trace ← IO.ofExcept (trace.start (occurrence "punctuation-producer") 10 "read")
  let trace ← IO.ofExcept (trace.finish (occurrence "punctuation-producer") 20 "1 // / -")
  let trace ← IO.ofExcept (trace.start (occurrence "punctuation-consumer") 30 "1 // / -")
  let trace ← IO.ofExcept (trace.finish (occurrence "punctuation-consumer") 40 "done")
  check (trace.graph.snapshot.isEmpty) "numeric literals or delimiters created a consumption relation"

def main : IO Unit := do
  checkElidedReads
  let (rows, packet) ← checkSource
  checkFeedback rows packet
  checkTrace
  checkRepeatedPositions
  checkKinds
  IO.println "Lean extraction checks passed: literal reads/citations, exact IDs, original Unicode coordinates, actual proposal order and usage labels"
