module

public import Eggshell.Matcher

@[expose] public section

namespace Eggshell.PilotSimilarityControl

/-- Deliberately fallible experimental assumption: admit semantic retrieval
to the ordinary run-local identity lane. No other Match field changes. -/
def promote (semantic : Bool) (matched : Matcher.Match) : Matcher.Match :=
  if semantic && matched.retrieved then {matched with retrieved := false} else matched

/-- Only the isolated experimental executable imports this adapter. Retain
the original retrieval nominations before changing their admission lane. -/
def apply (semantic : Bool) (rows : List Matcher.Match) : IO (List Matcher.Match) := do
  unless (← IO.getEnv "EGGSHELL_PILOT_SIMILARITY_CONTROL") == some "1" do
    throw (IO.userError "isolated similarity control requires its explicit experiment marker")
  if semantic then
    let nominations := rows.filter (·.retrieved)
    unless nominations.isEmpty do
      let some root ← IO.getEnv "EGGSHELL_DATA_ROOT" |
        throw (IO.userError "similarity control requires a private data root")
      IO.FS.createDirAll root
      let record := Lean.Json.mkObj [
        ("kind", Lean.toJson "experimental-similarity-identity-nomination"),
        ("monotonicMs", Lean.toJson (← IO.monoMsNow)),
        ("matches", Lean.toJson (nominations.map fun matched => Lean.Json.mkObj [
          ("owner", Persistence.valueToJson matched.edge.relation),
          ("demand", Persistence.valueToJson matched.demand),
          ("currentFragment", Persistence.valueToJson matched.work.currentFragment),
          ("pastFragment", Persistence.valueToJson matched.work.pastFragment),
          ("subwork", Lean.toJson matched.work.subwork),
          ("incomingFragmentIdentity", Lean.toJson matched.work.fragmentIdentity)]))]
      IO.FS.withFile (System.FilePath.mk root / "pilot-similarity-control.jsonl") .append fun handle =>
        handle.putStrLn record.compress
  pure (rows.map (promote semantic))

end Eggshell.PilotSimilarityControl
