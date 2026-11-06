module
public import Eggshell.Receipt
@[expose] public section
namespace Eggshell.Research.ReplyFootprint
open Lean

/-- Explicitly enabled model-free diagnostics only. The request owner writes
one private immutable witness, never a DB row or shared derived index. -/
def capture (id payload : String) : IO Unit := do
  unless (← IO.getEnv "EGGSHELL_RESEARCH_REPLY_FOOTPRINT") == some "1" do return
  unless Receipt.validId id do throw (IO.userError "reply witness needs an operation identity")
  let bytes := payload.toUTF8
  unless bytes.size ≤ 32*1024*1024 do throw (IO.userError "diagnostic reply witness exceeds its bound")
  let folder := (← Paths.dataRoot)/"reply-witnesses"
  FileSystem.rejectSymlinkAncestors folder
  FileSystem.privateDirectory folder
  let file := folder/(id++".json")
  FileSystem.immutableExistingBytes file bytes
  FileSystem.privateFile file

end Eggshell.Research.ReplyFootprint
