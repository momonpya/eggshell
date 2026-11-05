import Eggshell.CanonicalSourceLease
open Lean Eggshell.Synapses.CanonicalSource
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def main : IO Unit := do
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let input := base/"private-pages-smoke1-result/private/sessions/cpu-wave-a-0/pending.json"
  let root ← IO.ofExcept (Json.parse (← IO.FS.readFile input))
  let inputs ← IO.ofExcept (((root.getObjValD "preparedInputs").getObjValD "payload").getObjValAs? (Array Json) "inputs")
  check (inputs.size == 16) "retained read cut changed"
  let mut costs := #[]
  for entry in inputs do
    let canonical ← IO.ofExcept ((entry.getObjValD "canonical").getArr?)
    let some metadata := canonical[1]? | throw (IO.userError "missing captured canonical metadata")
    let source := entry.getObjValD "source"
    -- A real scope is a64-character lowercase digest, with the same serialized
    -- byte width as this placeholder. No capability or query is copied.
    let identityBytes := (toJson (String.ofList (List.replicate 64 '0'),source,metadata)).compress.utf8ByteSize
    costs := costs.push (Json.mkObj [("source",source.getObjValD "identity"),("identityBytes",toJson identityBytes),
      ("existingCharge",toJson (65536+8*identityBytes)),
      ("headEqualsResidentMetadata",toJson (source == metadata.getObjValD "source"))])
  let perQuery := costs.foldl (fun total row => total+(row.getObjValAs? Nat "existingCharge").toOption.getD 0) 0
  let mut budget : Shared.Budget Leases.capacity := {}
  let mut admitted := 0
  let mut rejected := 0
  for _ in [:80] do
    for row in costs do
      let amount ← IO.ofExcept (row.getObjValAs? Nat "existingCharge")
      match budget.reserve? amount with
      | some next => budget := next; admitted := admitted+1
      | none => rejected := rejected+1
  check (rejected > 0 && budget.used ≤ Leases.capacity) "existing admission did not reproduce pressure"
  let report := Json.mkObj [("capturedSources",toJson inputs.size),("targetConcurrentRequests",toJson (80 : Nat)),
    ("capacityUnchanged",toJson Leases.capacity),("maxHandlesUnchanged",toJson Leases.maxHandles),
    ("perQueryReservationBytes",toJson perQuery),("eightyQueryReservationBytes",toJson (80*perQuery)),
    ("maximumCompleteSimultaneousCutsByBytes",toJson (Leases.capacity/perQuery)),
    ("withoutReleaseAdmittedSourceTokens",toJson admitted),("withoutReleaseRejectedSourceTokens",toJson rejected),
    ("sources",toJson costs),("actualBudgetImplementationUsed",toJson true),
    ("notAReplayOfTheObservedScheduling",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/private-pages/lease-budget-replay.json" report.pretty
