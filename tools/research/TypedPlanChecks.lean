module
public import Eggshell.Handoff
public import Eggshell.Sha256
public import Lean
@[expose] public section
namespace Eggshell.Research.TypedPlanChecks
open Lean Plugin Synapses
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
#print axioms SourceViewBatch.Plan.wire_exact

/-- Independent copy of the parent's local JSON-AST handoff. It does not add
string compression or wire parsing that the parent never performed. -/
@[noinline,nospecialize] def parentQuery (query : SharedRangeAdapter.ServiceQuery) :
    Except String SharedRangeAdapter.ServiceQuery := fromJson? (toJson query)
@[noinline,nospecialize] def directQuery (query : SharedRangeAdapter.ServiceQuery) :
    Except String SharedRangeAdapter.ServiceQuery := .ok query
@[noinline,nospecialize] def parentChoice (plan : SourceViewBatch.Plan) :
    Except String SharedRangeAdapter.ServiceChoice := do
  let encoded := Json.mkObj [("identities",toJson plan.identities),("lease",toJson plan.lease),("choice",toJson plan.choice)]
  unless encoded.getObjValD "identities" == toJson plan.identities && encoded.getObjValD "lease" == toJson plan.lease do
    throw "parent envelope changed its pinned source views"
  fromJson? (encoded.getObjValD "choice")
@[noinline,nospecialize] def directChoice (plan : SourceViewBatch.Plan) :
    Except String SharedRangeAdapter.ServiceChoice := .ok plan.choice

theorem direct_query_exact (query : SharedRangeAdapter.ServiceQuery) : directQuery query = .ok query := rfl
theorem direct_choice_exact (plan : SourceViewBatch.Plan) : directChoice plan = .ok plan.choice := rfl

def timed (action : Unit → Except String α) : IO (α × Nat) := do
  let began ← IO.monoNanosNow
  let result ← IO.ofExcept (action ())
  return (result,((← IO.monoNanosNow)-began)/1000)

def run (fixture : System.FilePath) (expected : String) (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous transfer evidence"
  let bytes ← IO.FS.readBinFile fixture
  check (Sha256.hex bytes == expected) "fixed real selector input changed"
  let some text := String.fromUTF8? bytes | throw (IO.userError "selector input is not UTF-8")
  let cases ← IO.ofExcept (Json.parse text >>= Json.getArr?)
  check (cases.size == 3) "all three fixed selector inputs required"
  let mut observations := #[]
  for (item,index) in cases.zipIdx do
    let query ← IO.ofExcept (item.getObjValAs? SharedRangeAdapter.ServiceQuery "query")
    let choice ← IO.ofExcept (item.getObjValAs? SharedRangeAdapter.ServiceChoice "choice")
    check query.valid "fixed selector input is invalid"
    let plan : SourceViewBatch.Plan := {identities := #[item.getObjValD "heads"],lease := "fixed-transfer-check",choice}
    let reference := toJson query
    let planJson := toJson plan
    check (toJson (← IO.ofExcept (fromJson? planJson : Except String SourceViewBatch.Plan)) == planJson)
      "wire envelope roundtrip changed"
    let mut trials := #[]
    for repetition in [:3] do
      let oldFirst := repetition%2 == 0
      let (oldQuery,newQuery) ← if oldFirst then do
          let old ← timed fun _ => parentQuery query
          let fresh ← timed fun _ => directQuery query
          pure (old,fresh)
        else do
          let fresh ← timed fun _ => directQuery query
          let old ← timed fun _ => parentQuery query
          pure (old,fresh)
      let (oldChoice,newChoice) ← if oldFirst then do
          let old ← timed fun _ => parentChoice plan
          let fresh ← timed fun _ => directChoice plan
          pure (old,fresh)
        else do
          let fresh ← timed fun _ => directChoice plan
          let old ← timed fun _ => parentChoice plan
          pure (old,fresh)
      check (toJson oldQuery.1 == reference && toJson newQuery.1 == reference &&
        toJson oldChoice.1 == toJson choice && toJson newChoice.1 == toJson choice)
        "typed handoff changed query or choice"
      trials := trials.push (Json.mkObj [("repetition",toJson repetition),("parentFirst",toJson oldFirst),
        ("parentQueryUs",toJson oldQuery.2),("typedQueryUs",toJson newQuery.2),
        ("parentChoiceUs",toJson oldChoice.2),("typedChoiceUs",toJson newChoice.2),("payloadExact",toJson true)])
    observations := observations.push (Json.mkObj [("case",toJson index),("owners",toJson query.owners.size),
      ("genericUnits",toJson query.generic.size),("pieces",toJson query.pieces.length),
      ("queryJsonBytesOutsideTiming",toJson reference.compress.utf8ByteSize),("trials",toJson trials)])
  check (!(fromJson? (Json.mkObj []) : Except String SourceViewBatch.Plan).isOk) "malformed wire envelope accepted"
  IO.FS.writeFile output (Json.mkObj [("fixtureSha256",toJson expected),
    ("runtimeSha256",toJson (Sha256.hex (← IO.FS.readBinFile (← IO.appPath)))),
    ("observations",toJson observations),("allQueriesAndChoicesExact",toJson true),
    ("sameAstBoundaryAsParent",toJson true),("hookOrMemoryEffectEstablished",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.TypedPlanChecks
