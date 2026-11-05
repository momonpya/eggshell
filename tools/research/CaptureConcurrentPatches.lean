import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def patch (before after : System.FilePath) (relative : String) : IO String := do
  let found ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--unified=0",before.toString,after.toString]}
  check (found.exitCode ≤ 1) "source patch failed"
  if found.stdout.isEmpty then return ""
  let lines := found.stdout.splitOn "\n"
  let lines := lines.map fun line =>
    if line.startsWith "diff --git " then s!"diff --git a/{relative} b/{relative}" else
    if line.startsWith "--- " then (if before.toString == "/dev/null" then "--- /dev/null" else s!"--- a/{relative}") else
    if line.startsWith "+++ " then s!"+++ b/{relative}" else line
  return String.intercalate "\n" lines
def save (name : String) (rows : Array (System.FilePath × System.FilePath × String)) : IO Unit := do
  let mut source := ""
  for (before,after,relative) in rows do source := source++(← patch before after relative)
  IO.FS.writeFile (workspace/"docs/candidates"/name/"candidate.patch") source
def main (arguments : List String) : IO Unit := do
  let core := base/"interest-traffic-core"
  if arguments == ["query-stages"] then
    check (!(← (workspace/"docs/candidates/query-stages/candidate.patch").pathExists)) "query-stage patch already sealed"
    save "query-stages" ((#["Eggshell/Handoff.lean","Eggshell/Worker.lean","Eggshell/OperationPool.lean"] : Array String).map fun (relative : String) =>
      (base/"query-stages-parent-core"/relative,core/relative,relative))
    let mut initial := ""
    for relative in (["Eggshell/Handoff.lean","Eggshell/Worker.lean","Eggshell/OperationPool.lean"] : List String) do
      initial := initial++(← patch (base/"query-stages-parent-core"/relative) (base/"query-stages-initial-core"/relative) relative)
    IO.FS.writeFile (workspace/"docs/candidates/query-stages/initial-observer.patch") initial
    return
  if arguments == ["source-protocol"] then
    check (!(← (workspace/"docs/candidates/source-protocol/candidate.patch").pathExists))
      "task completion patches already sealed"
    let files : Array String := #["Eggshell/TaskDeadline.lean","Eggshell/OperationPool.lean",
      "Eggshell/PublicationService.lean","Eggshell/ContractAudit.lean"]
    save "source-protocol" (files.map fun (relative : String) =>
      (base/"task-observer-parent-core"/relative,core/relative,relative))
    let partialCore := base/"task-observer-sealed-core"
    IO.FS.createDirAll (partialCore/"Eggshell")
    let mut partialPatch := ""
    for relative in files do
      let cacheName := relative.replace "/" "_" |>.replace ".lean" ".source"
      let cache ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"task-observer-build"/cacheName)))
      let source ← IO.ofExcept ((← IO.ofExcept cache.getArr?)[0]!.getStr?)
      IO.FS.writeFile (partialCore/relative) source
      partialPatch := partialPatch++(← patch (base/"task-observer-parent-core"/relative)
        (partialCore/relative) relative)
    IO.FS.writeFile (workspace/"docs/candidates/source-protocol/partial-observer.patch") partialPatch
    let entry ← patch (workspace/"tools/research/SessionDispatchChecks.lean")
      (core/"tools/research/SessionDispatchChecks.lean") "tools/research/SessionDispatchChecks.lean"
    IO.FS.writeFile (workspace/"docs/candidates/source-protocol/entry.patch") entry
    return
  check arguments.isEmpty "unknown patch capture selection"
  check (!(← (workspace/"docs/candidates/shared-leases/combined.patch").pathExists)) "candidate patch already sealed"
  check ((← IO.FS.readFile (core/"Eggshell/CanonicalSourceLease.lean")).contains "structure Descriptor where")
    "capture requires the isolated candidate source"
  IO.FS.createDirAll (workspace/"docs/candidates/shared-leases")
  save "direct-waits" ((#["Eggshell/TaskDeadline.lean","Eggshell/Numerical.lean","Eggshell/PublicationService.lean"] : Array String).map fun (relative : String) =>
    (base/"direct-waits-parent-core"/relative,
     (if relative == "Eggshell/PublicationService.lean" then base/"shared-leases-parent-core"/relative else core/relative),relative))
  save "private-pages" ((#["Eggshell/DB/PageMap.lean","Eggshell/PreparedReaders.lean","Eggshell/OperationPool.lean"] : Array String).map fun (relative : String) =>
    (base/"private-pages-parent-core"/relative,core/relative,relative))
  let entry ← patch (workspace/"tools/research/SessionDispatchChecks.lean")
    (core/"tools/research/SessionDispatchChecks.lean") "tools/research/SessionDispatchChecks.lean"
  IO.FS.writeFile (workspace/"docs/candidates/shared-leases/entry.patch") entry
  save "shared-leases" ((#["Eggshell/CanonicalSourceLease.lean","Eggshell/Handoff.lean"] : Array String).map fun (relative : String) =>
    (base/"shared-leases-parent-core"/relative,core/relative,relative))
  let mut combined := ""
  for relative in (#["Eggshell/OperationPlan.lean","Eggshell/OperationPool.lean","Eggshell/PublicationService.lean",
      "Eggshell/PreparedReaders.lean","Eggshell/Worker.lean","Eggshell/Numerical.lean",
      "Eggshell/Handoff.lean","Eggshell/SearchRank.lean","Main.lean"] : Array String) do
    combined := combined++(← patch (base/"session-dispatch-baseline-core"/relative) (core/relative) relative)
  for (parent,relative) in (#[
      ("direct-waits-parent-core","Eggshell/TaskDeadline.lean"),
      ("private-pages-parent-core","Eggshell/DB/PageMap.lean"),
      ("shared-leases-parent-core","Eggshell/CanonicalSourceLease.lean")] : Array (String × String)) do
    combined := combined++(← patch (base/parent/relative) (core/relative) relative)
  combined := combined++(← patch "/dev/null" (core/"Eggshell/SearchReaders.lean") "Eggshell/SearchReaders.lean")
  combined := combined++(← patch (base/"shared-leases-parent-core/Eggshell/PublicationClient.lean")
    (core/"Eggshell/PublicationClient.lean") "Eggshell/PublicationClient.lean")
  IO.FS.writeFile (workspace/"docs/candidates/shared-leases/combined.patch") combined
  let mut hosted := ""
  for relative in (["Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean"] : List String) do
    hosted := hosted++(← patch (base/"hosted-endpoint-parent-core"/relative) (core/relative) relative)
  IO.FS.writeFile (workspace/"docs/candidates/shared-leases/hosted-endpoint.patch") hosted
