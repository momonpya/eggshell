import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def replaceOnce (source before after : String) : IO String := do
  unless (source.splitOn before).length == 2 do
    throw (IO.userError "expected one exact lifecycle edit location")
  return source.replace before after

def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/worker-lifecycle-20261025"
  let parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/snapshot-refresh-20261025"
  unless !(← root.pathExists) do throw (IO.userError "keep previous lifecycle candidate")
  IO.FS.createDir root
  let cloned ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(parent / "checkout").toString,(root / "checkout").toString]}
  unless cloned.exitCode == 0 do throw (IO.userError "clone lifecycle candidate failed")
  let original ← IO.FS.readFile (parent / "checkout/Eggshell/Worker.lean")
  let mut worker ← replaceOnce original "public import Std.Sync.Mutex" "public import Std.Sync.Mutex\npublic import Eggshell.WorkerLifetime"
  worker ← replaceOnce worker
    "  child : Std.Mutex (Option Child)\n\ninitialize slots : Std.Mutex (List (String × Slot)) ← Std.Mutex.new []"
    "  child : Std.Mutex (Lifetime.Cell (Option Child))\n\ninitialize slots : Std.Mutex (Lifetime.Cell (List (String × Slot))) ← Std.Mutex.new (.open [])"
  worker ← replaceOnce worker
    "  if let some (_, slot) := (← get).find? (·.1 == key) then return slot\n  let slot := { gate := ← Std.Mutex.new (), child := ← Std.Mutex.new none }\n  modify ((key, slot) :: ·)\n  pure slot"
    "  match ← get with\n  | .closed => pure {gate := ← Std.Mutex.new (), child := ← Std.Mutex.new .closed}\n  | .open current =>\n      if let some (_, slot) := current.find? (·.1 == key) then return slot\n      let slot := { gate := ← Std.Mutex.new (), child := ← Std.Mutex.new (.open none) }\n      set (Lifetime.Cell.open ((key, slot) :: current))\n      pure slot"
  worker ← replaceOnce worker "    if let some child ← get then killGroup child"
    "    match Lifetime.admit (← get) with\n    | .reuse child => killGroup child\n    | _ => pure ()"
  worker ← replaceOnce worker
    "def retire (slot : Slot) (child : Child) : IO Unit := slot.child.atomically do\n  if let some current ← get then\n    if current.pid == child.pid then\n      killGroup child\n      let _ ← child.wait\n      set (none : Option Child)"
    "def retire (slot : Slot) (child : Child) : IO Unit := do\n  let owned ← slot.child.atomically do\n    let (state, owned) := Lifetime.release (fun current => current.pid == child.pid) (← get)\n    set state\n    pure owned\n  if let some owned := owned then\n    killGroup owned\n    let _ ← owned.wait\n    pure ()"
  worker ← replaceOnce worker
    "      match ← get with\n      | some child => pure child\n      | none =>\n          let child ← IO.Process.spawn {"
    "      match Lifetime.admit (← get) with\n      | .refused => pure none\n      | .reuse child => pure (some child)\n      | .spawn =>\n          let child ← IO.Process.spawn {"
  worker ← replaceOnce worker "          set (some child)\n          pure child\n    try"
    "          set (Lifetime.Cell.open (some child))\n          pure (some child)\n    let some child := child | return none\n    try"
  worker ← replaceOnce worker
    "def shutdown : IO Unit := slots.atomically do\n  for (_, slot) in ← get do\n    let child ← slot.child.atomically get\n    if let some child := child then retire slot child\n  set ([] : List (String × Slot))"
    "/-- Seal admission before waiting for any process. Old slots and late callers\ncan no longer create a child; each existing child has one retiring owner. -/\ndef shutdown : IO Unit := do\n  let owned ← slots.atomically do\n    let (state, owned) := Lifetime.close (← get)\n    set state\n    pure (owned.getD [])\n  for (_, slot) in owned do\n    let child ← slot.child.atomically do\n      let (state, owned) := Lifetime.close (← get)\n      set state\n      pure (owned.bind id)\n    if let some child := child then\n      killGroup child\n      let _ ← child.wait\n      pure ()"
  worker ← replaceOnce worker "  let now ← IO.monoMsNow\n  if now ≥ deadline then return none\n  let probe ← gate.tryAtomically"
    "  if ← IO.checkCanceled then return none\n  let now ← IO.monoMsNow\n  if now ≥ deadline then return none\n  let probe ← gate.tryAtomically"
  worker ← replaceOnce worker "  let now ← IO.monoMsNow\n  if now ≥ deadline then return none\n  match gateDecision"
    "  if ← IO.checkCanceled then return none\n  let now ← IO.monoMsNow\n  if now ≥ deadline then return none\n  match gateDecision"
  let mut daemon ← IO.FS.readFile (parent / "checkout/Eggshell/Daemon.lean")
  daemon ← replaceOnce daemon "    Worker.shutdown\n    removeEndpointIfOwned endpoint\n    pure 0\n  catch error =>\n    removeEndpointIfOwned endpoint\n    IO.eprintln s!\"eggshelld: {error}\"\n    pure 1"
    "    pure 0\n  catch error =>\n    IO.eprintln s!\"eggshelld: {error}\"\n    pure 1\n  finally\n    for task in clients ++ saves ++ indexes do IO.cancel task\n    Worker.shutdown\n    removeEndpointIfOwned endpoint"
  for (relative, text) in #[("Eggshell/Worker.lean",worker),("Eggshell/Daemon.lean",daemon),
      ("Eggshell/WorkerLifetime.lean",← IO.FS.readFile (project / "tools/research/worker-lifecycle/Eggshell/WorkerLifetime.lean"))] do
    let destination := root / "checkout" / relative
    if ← destination.pathExists then
      if (← destination.symlinkMetadata).type == .symlink then IO.FS.removeFile destination
    IO.FS.writeFile destination text
    let retained := project / "tools/research/worker-lifecycle" / relative
    IO.FS.createDirAll retained.parent.get!
    IO.FS.writeFile retained text
  let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (parent / "build-plan.json")))
  let inherited ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  let settings := settings.setObjVal! "core" (toJson (root / "checkout").toString)
    |>.setObjVal! "output" (toJson (root / "build").toString)
    |>.setObjVal! "parents" (toJson (inherited.push parent.toString))
    |>.setObjVal! "force" (toJson #["Eggshell.Warm","Eggshell.Worker","Eggshell.Daemon","Main"])
  IO.FS.writeFile (root / "build-plan.json") (settings.pretty ++ "\n")
  IO.println "prepared isolated terminal worker admission"
