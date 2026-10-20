module

public import Eggshell.Warm

@[expose] public section

namespace Eggshell.Plugin.SourceReadiness
open Lean

/-- Leave two thirds of the remaining hook window for retrieval and fallback.
The manager retains its independent semantic cutoff and original hard deadline. -/
def waitDeadline (now upstream : Nat) : Nat := min upstream (now + (upstream - now) / 3)

theorem deadline_bounded (now upstream : Nat) : waitDeadline now upstream ≤ upstream :=
  Nat.min_le_left _ _

/-- Warm markers schedule work only. Search still checks every source record.
Exact live-root lookup also prevents an older warm publication or a retracted
node from satisfying a new observation. This reader does not publish or index. -/
def ready (owner : DB.Sidecar.Owner) (command : List String) (roots : List Value) : IO Bool := do
  let snapshot ← owner.pin
  let mut warm := false
  for storage in [DB.Sidecar.Storage.database, .user] do
    let target : IndexTarget := {owner, command, storage}
    if !(← Warm.required target snapshot) then warm := true
  unless warm do return false
  roots.allM fun root => return (← Persistence.Store.liveRoot? snapshot root).isSome

/-- Only observed current-turn work with an active writable authority can wait
for its existing save/index producer. Read-only profiles, custom providers and
lexical search retain their normal path. No staged value is filtered. -/
def wait (pending : PendingTurn) (upstream : Nat) (receipt : Option String) : IO Bool := do
  let some path := pending.write | return true
  unless pending.read.contains path && !pending.tools.isEmpty do return true
  let some command := pending.semanticMatcher | return true
  let _ :: "search-provider" :: _ := command | return true
  if Warm.lexicalOnly command then return true
  let roots := observedRoots pending
  let started ← IO.monoMsNow
  let deadline := waitDeadline started upstream
  let mut complete := false
  let mut available := true
  try
    let owner := DB.Sidecar.Owner.ofSnapshot (← DB.PageMap.pin (.mk path))
    while (← IO.monoMsNow) < deadline do
      if ← ready owner command roots then
        complete := true
        break
      IO.sleep 25
  catch _ => available := false
  Receipt.observe receipt "source-readiness" (Json.mkObj [
    ("complete", toJson complete), ("available", toJson available),
    ("observations", toJson roots.length), ("waitMs", toJson ((← IO.monoMsNow) - started)),
    ("deadlineMs", toJson deadline), ("upstreamDeadlineMs", toJson upstream)])
  return complete

end Eggshell.Plugin.SourceReadiness
