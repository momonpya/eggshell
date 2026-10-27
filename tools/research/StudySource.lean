import Eggshell.GraphStore
open Lean Eggshell

namespace Eggshell.Research.StudySource

structure Result where
  source : DB.PageMap.Head
  checked : Nat
  complete : Bool
  failedRevision : Option Nat
  error : Option String
  deriving ToJson

/-- Validate the exact publication ancestry before a study uses old knowledge.
This is off-hook admission work; it neither repairs nor defaults stored data. -/
def inspect (path : System.FilePath) : IO Result := do
  let source ← DB.PageMap.pin path
  let mut current := source.head
  let mut checked := 0
  let mut failure := none
  while current.revision > 0 do
    try
      let publication ← Persistence.Store.readPublication {source with head := current} current.revision
      current := publication.parent
      checked := checked+1
    catch error => failure := some error.toString; break
  let retained ← DB.PageMap.pin path
  unless retained.head == source.head do throw (IO.userError "source changed during ancestry admission")
  return ⟨source.head,checked,failure.isNone,
    if failure.isSome then some current.revision else none,failure⟩

def requireValid (result : Result) : IO Unit :=
  unless result.complete do throw (IO.userError
    s!"source publication ancestry is unreadable at {result.source.identity} revision {result.failedRevision}: {result.error}")

def verify (path : System.FilePath) : IO Result := do
  let result ← inspect path
  requireValid result
  return result

end Eggshell.Research.StudySource
