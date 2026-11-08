module
public import Eggshell.Handoff
@[expose] public section

namespace Eggshell.Research.EmptyCitationGuard
open Plugin

theorem empty_coordinates (owner : OutcomeEdge) (records : List SourceEvidence.Record) :
    rankedCitedObservationCoordinates [] owner records = none := by
  unfold rankedCitedObservationCoordinates
  cases Matcher.atomText? owner.outcome with
  | none => rfl
  | some source =>
    cases Matcher.atomText? owner.work with
    | none => rfl
    | some work => rfl

/-- No producer, cache or parsing is needed when no interpretation nominated
a citation. This is a general absence test, not a query-specific rule. -/
def query (texts : List (Nat × String)) (owner : OutcomeEdge) (records : List SourceEvidence.Record) :=
  if texts.isEmpty then none else rankedCitedObservationCoordinates texts owner records

theorem query_exact (texts : List (Nat × String)) (owner : OutcomeEdge)
    (records : List SourceEvidence.Record) :
    query texts owner records = rankedCitedObservationCoordinates texts owner records := by
  cases texts with
  | nil => simp [query,empty_coordinates]
  | cons first rest => rfl

end Eggshell.Research.EmptyCitationGuard
