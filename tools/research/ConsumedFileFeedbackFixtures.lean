import Eggshell.SynapseJournal
open Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

namespace Eggshell.Research.ConsumedFileFeedback

#print axioms consumed_source_has_witness
#print axioms consumed_source_is_later
#print axioms consumed_omission_requires_stored

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- These are immutable source/consumption cases, not the benchmark's names,
gold coordinates or an alternative selection objective. -/
def fixtures : IO Unit := do
  let fingerprint := String.ofList (List.replicate 64 'a')
  let file : File := ⟨"resources/observed.txt", fingerprint, 1024⟩
  let requested : Range := ⟨file, 7, 7⟩
  let enclosing : Range := ⟨.original ⟨"complete-work", fingerprint, 80⟩, 1, 80⟩
  let producer : Occurrence := ⟨"first-session", "first-turn", "read"⟩
  let consumer : Occurrence := ⟨"first-session", "first-turn", "use"⟩
  let rows : Array OutputRow := #[⟨enclosing, 0, 80⟩, ⟨requested, 10, 16⟩]
  let edge : Consumption := {
    producer, consumer, producerFinish := 1, consumerStart := 2,
    kind := .identifier, term := "needle", inputFirst := 0, inputLimit := 6,
    outputFirst := 10, outputLimit := 16, rows := project rows 10 16}
  check (edge.rows == #[requested]) "file correspondence did not supersede its original container"
  let some consumed := consumedSource? edge requested | throw (IO.userError "actual file consumption was rejected")
  let query := String.ofList (List.replicate 64 'b')
  let some used := consumedUsage? consumed query #[requested] #[] |
    throw (IO.userError "saved and omitted file consumption earned no feedback")
  check (used.source == requested && used.event.consumption == some ⟨consumer, requested⟩ &&
    used.kind == .omittedThenConsumed && used.valid) "file usage lost its actual source or consumer"
  check ((consumedUsage? consumed query #[] #[]).isNone) "a newly discovered range was labelled missed memory"
  check ((consumedUsage? consumed query #[requested] #[requested]).isNone) "a delivered range was labelled omitted"
  let changedFile : File := {file with fingerprint := query}
  let changed : Range := ⟨changedFile, 7, 7⟩
  check ((consumedUsage? consumed query #[changed] #[]).isNone) "a different file version earned a reuse label"
  check ((consumedSource? edge ⟨file, 8, 8⟩).isNone) "an unconsumed sibling line earned feedback"
  check ((consumedSource? edge ⟨file, 0, 7⟩).isNone) "invalid source coordinates earned feedback"
  check ((consumedSource? {edge with consumerStart := 1} requested).isNone)
    "noncausal consumption earned feedback"
  let original := {edge with rows := #[enclosing]}
  let some general := consumedSource? original enclosing |
    throw (IO.userError "general non-file output consumption regressed")
  check ((consumedUsage? general query #[enclosing] #[]).isSome) "general output consumption lost feedback"
  let duplicate := {edge with rows := #[requested, requested]}
  let some repeated := consumedSource? duplicate requested | throw (IO.userError "duplicate witnesses were rejected")
  check (consumedUsage? repeated query #[requested, requested] #[] == some used)
    "duplicating identical source evidence changed the usage fact"
  let graph ← IO.ofExcept (recordConsumed (← IO.ofExcept (Graph.ofFacts #[])) consumed query #[requested] #[])
  check (graph.snapshot == #[.used used]) "actual graph did not retain the file-consumption fact"

end Eggshell.Research.ConsumedFileFeedback
