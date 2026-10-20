module

public import Eggshell.Warm

@[expose] public section

namespace Eggshell.Plugin.IndexCompletion

open Lean

/-- A drain's warm hint can precede the worker's pinned publication. Valid
tickets therefore require complete discovery and focus coverage independently
of that hint. Only the common warm path owns the index claim and encoder. -/
def run (target : IndexTarget) (paths : List System.FilePath) (warm : Bool) : IO Nat := do
  let pinned ← target.owner.pin
  let directory ← target.indexes pinned
  let mut tickets : List System.FilePath := []
  for path in paths.eraseDups do
    let path ← DB.PageMap.absolute path
    if path.parent != some directory then
      IO.eprintln "Eggshell refused an index ticket outside its DB lane"
      continue
    try
      if !(← path.pathExists) then continue
      let ticket ← (readBoundedJson path 1048576 : IO IndexTicket)
      unless ticket.database == pinned.head.identity &&
          ticket.provider == indexProviderKey target.command &&
          ticket.authority == pinned.head.authority do
        throw (IO.userError "index ticket belongs to another DB or provider")
      let owners ← Persistence.Store.owners pinned ticket.roots
      let _ ← resolveIndexTicket owners ticket
      tickets := tickets ++ [path]
    catch error =>
      if ← path.pathExists then quarantine path
      IO.eprintln s!"Eggshell retained or quarantined an invalid index ticket: {error}"
  if tickets.isEmpty && !warm then return 0
  let _ ← Warm.runTarget pinned target
  for path in tickets do removeIfExists path
  return tickets.length

end Eggshell.Plugin.IndexCompletion
