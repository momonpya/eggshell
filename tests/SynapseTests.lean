import Eggshell.Synapses

open Lean Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def source (first := 10) (last := 12) (fingerprint := String.ofList (List.replicate 64 'a')) : Range :=
  {subject := .file {relative := "src/日本語.cpp", fingerprint, bytes := 1000}, first, last}

private def occurrence (session : String) : Occurrence := ⟨session, "turn", "read"⟩

private def claim (session : String) : Claim := ⟨"database", session, 0, 100⟩

private def readFor (session : String) (range := source) : Read :=
  {occurrence := occurrence session,source := range,binding := ⟨"database",session,"work",0,100⟩}

private def query : String := String.ofList (List.replicate 64 'b')

private def sessionGraph (session : String) : Except String Graph := do
  let range := source
  let read := readFor session
  let support ← Support.checked read range (claim session)
  let graph ← Graph.ofFacts #[.read read, .supports support, .coquoted (.answer "database" session) range]
  graph.recordRead ⟨occurrence session, 0, none⟩ query range #[range] #[] true

private def mergeLaws : IO Unit := do
  let a ← IO.ofExcept (sessionGraph "A")
  let b ← IO.ofExcept (sessionGraph "B")
  let c ← IO.ofExcept (sessionGraph "C")
  let combined ← IO.ofExcept (a.merge b)
  check (combined.rangeCount == 1) "same range split by session"
  check ((combined.sourceBindings source).size == 2) "original bindings lost"
  check ((combined.usageCounts source).omittedThenRead == 2) "new session did not contribute evidence"
  check ((← IO.ofExcept (combined.merge a)).snapshot == combined.snapshot) "replay increased weight"
  check ((← IO.ofExcept (a.merge a)).snapshot == a.snapshot) "join is not idempotent"
  check ((← IO.ofExcept (b.merge a)).snapshot == combined.snapshot) "join depends on order"
  let left ← IO.ofExcept ((← IO.ofExcept (a.merge b)).merge c)
  let right ← IO.ofExcept (a.merge (← IO.ofExcept (b.merge c)))
  check (left.snapshot == right.snapshot) "join depends on grouping"
  let restored ← IO.ofExcept ((fromJson? (toJson combined.snapshot) : Except String (Array Fact)) >>= Graph.ofFacts)
  check (restored.snapshot == combined.snapshot) "native JSON roundtrip changed evidence"
  let conflict ← IO.ofExcept (Graph.empty.recordRead ⟨occurrence "A", 0, none⟩ query source #[source] #[source] true)
  check ((!(a.merge conflict).isOk)) "conflicting usage event silently overwritten"
  check ((a.usageCounts source).omittedThenRead == 1) "failed join changed its input"

private def boundaries : IO Unit := do
  check (covered (source 1 10) #[source 1 4, source 5 10]) "adjacent intervals do not cover"
  check (!(covered (source 1 10) #[source 1 4, source 6 10])) "gap was covered"
  let changed := source 10 12 (String.ofList (List.replicate 64 'c'))
  check (!(covered source #[changed])) "different fingerprints were merged"
  check (readKind source #[source] #[] false == .reread) "unchecked read labelled omitted"
  check (readKind source #[source] #[source] true == .reread) "delivered read labelled omitted"
  check (readKind changed #[source] #[] true == .sourceChanged) "changed source labelled omitted"
  check (!(covered (source 1 (10^30)) #[source 1 4])) "unbounded line range expanded"
  let invalid : Range := {source with first := 0}
  check ((!(Graph.ofFacts #[.read (readFor "invalid" invalid)]).isOk)) "invalid range admitted"
  let graph ← IO.ofExcept (Graph.ofFacts #[.read (readFor "old"), .read (readFor "changed" changed)])
  check (graph.rangeCount == 2) "source change shared one range node"

private def derivation : IO Unit := do
  let root := source 20 21
  let supporting ← IO.ofExcept (Support.checked (readFor "B" root) root (claim "B"))
  let edge : Consumption := {
    producer := occurrence "A", consumer := occurrence "B"
    producerFinish := 1, consumerStart := 2, kind := .pathLine, term := "src/日本語.cpp:10"
    inputFirst := 0, inputLimit := 17, outputFirst := 0, outputLimit := 17
    rows := #[source 10 10] }
  let graph ← IO.ofExcept (Graph.ofFacts #[
    .read (readFor "A" (source 1 100)), .supports supporting, .consumed edge])
  let relevant := graph.relevant #[claim "B"]
  check (relevant.ranges.size == 2 && relevant.ranges.contains root &&
    relevant.ranges.contains (source 10 10)) "reverse consumption lost witness rows"
  check (!(relevant.ranges.contains (source 1 100))) "whole ancestor read leaked into body candidates"
  check (relevant.occurrences.size == 2) "producer not reached from support"
  let future := {edge with producerFinish := 3}
  check ((!future.checked.isOk)) "future producer output admitted"
  let unsupported ← IO.ofExcept (graph.insert (.consumed {edge with rows := #[], kind := .identifier}))
  check ((unsupported.relevant #[claim "B"]).unlocated.size == 1) "unknown witness location was guessed"
  check ((!(Support.checked (readFor "A") (source 9 12) (claim "A")).isOk)) "citation outside read admitted"

private def hyperedges : IO Unit := do
  let facts := (Array.range 1000).map fun i => Fact.coquoted (.answer "db" "answer") (source (i+1) (i+1))
  let graph ← IO.ofExcept (Graph.ofFacts facts)
  check (graph.evidenceCount == 1000) "coquotation expanded into a quadratic clique"
  check ((graph.companions #[source 1 1, source 2 2]).size == 1000) "coquoted companions missing"
  check ((graph.companions #[source 1 1, source 2 2])[source 3 3]? == some 1)
    "one answer counted twice through two selected ranges"

def main : IO Unit := do
  mergeLaws
  boundaries
  derivation
  hyperedges
  IO.println "Lean synapse checks passed: cross-session join, immutable events, source boundaries, reverse derivation, coquotation"
