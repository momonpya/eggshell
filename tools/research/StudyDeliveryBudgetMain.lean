import Eggshell.Sha256
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean Eggshell
namespace Eggshell.Research.DeliveryBudget

structure State where
  used : Nat
  within : used ≤ 1

def spend (state : State) (missing : Nat) : Except String State :=
  if bound : state.used+missing ≤ 1 then .ok ⟨state.used+missing,bound⟩
  else .error "required memory omissions exceed the six-stage limit"

theorem spend_exact (state : State) (missing : Nat) (next : State)
    (accepted : spend state missing = .ok next) : next.used = state.used+missing := by
  unfold spend at accepted
  split at accepted
  · cases accepted; rfl
  · contradiction

structure Artifact where
  path : String
  sha256 : String
  deriving FromJson, ToJson, Inhabited

structure Request where
  stage : Nat
  repetition : Nat
  runtimeSha256 : String
  currentAudit : Artifact
  previous : Array Artifact
  output : String
  deriving FromJson

structure Requirement where
  name : String
  stored : Bool
  bodyDelivered : Bool
  deriving FromJson

private def check (b : Bool) (message : String) : IO Unit :=
  unless b do throw (IO.userError message)

private def read (artifact : Artifact) : IO Json := do
  let path := System.FilePath.mk artifact.path
  check (path.isAbsolute && (← path.metadata).byteSize ≤ 16*1024*1024) "bounded absolute delivery report required"
  let bytes ← IO.FS.readBinFile path
  check (Sha256.hex bytes == artifact.sha256) "delivery report digest changed"
  let some text := String.fromUTF8? bytes | throw (IO.userError "delivery report is not UTF-8")
  IO.ofExcept (Json.parse text)

def run (input : String) : IO Bool := do
  let request ← IO.ofExcept (Json.parse (← IO.FS.readFile input) >>= fromJson? (α := Request))
  check (1 ≤ request.stage && request.stage ≤ 6 && request.previous.size+1 == request.stage)
    "all previous stages in the same six-stage sequence are required"
  check (!(← (System.FilePath.mk request.output).pathExists)) "keep the previous delivery-budget decision"
  let mut state : State := ⟨0,by decide⟩
  for index in [:request.previous.size] do
    let previous ← read request.previous[index]!
    check ((previous.getObjValAs? Nat "stage").toOption == some (index+1) &&
      (previous.getObjValAs? Nat "repetition").toOption == some request.repetition &&
      (previous.getObjValAs? String "runtimeSha256").toOption == some request.runtimeSha256 &&
      (previous.getObjValAs? Bool "accepted").toOption == some true)
      "delivery-budget history is incomplete or belongs to another run"
    let missing ← IO.ofExcept (previous.getObjValAs? (Array String) "missingRequired")
    state ← IO.ofExcept (spend state missing.size)
  let audit ← read request.currentAudit
  let requirements ← IO.ofExcept (audit.getObjValAs? (Array Requirement) "requirements")
  let names := requirements.map (·.name)
  check (names.toList.eraseDups.length == names.size) "duplicate required-memory identities"
  let missing := (requirements.filter fun row => row.stored && !row.bodyDelivered).map (·.name)
  let admitted := spend state missing.size
  let report := Json.mkObj [
    ("stage",toJson request.stage),("repetition",toJson request.repetition),
    ("runtimeSha256",toJson request.runtimeSha256),("audit",toJson request.currentAudit),
    ("previous",toJson request.previous),("missingRequired",toJson missing),
    ("missingAcrossSequence",toJson (state.used+missing.size)),("maximumMissing",toJson (1 : Nat)),
    ("accepted",toJson admitted.isOk),("completeSixStageSequence",toJson (request.stage == 6)),
    ("requiredInDb",toJson ((requirements.filter (·.stored)).size))]
  IO.FS.writeFile request.output (report.pretty ++ "\n")
  return admitted.isOk

end Eggshell.Research.DeliveryBudget

def main (args : List String) : IO UInt32 := do
  try
    let [input] := args | throw (IO.userError "StudyDeliveryBudgetMain INPUT")
    return if ← Eggshell.Research.DeliveryBudget.run input then 0 else 1
  catch error => IO.eprintln error.toString; return 1
