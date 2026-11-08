import tools.research.SelectorFixture
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
namespace BaseCueDirectChecks
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
structure Case where
  query : ServiceQuery
  units : Array ServiceUnit
  pieces : List CuePiece
  source : Synapses.PreparedSourceView.Domain
  expected : ServiceChoice

/-- Call the unchanged native selectView directly, with the same immutable
inputs held once. No RPC, model, source read, hook, or candidate optimization. -/
@[noinline, nospecialize] def solve (sample : Case) (client ordinal : Nat) : IO Json := do
  let started ← IO.monoNanosNow
  let value := selectView sample.query sample.units sample.pieces sample.source
  let value ← (← IO.mkRef value).get
  let elapsed := (← IO.monoNanosNow)-started
  let some value := value | throw (IO.userError "unchanged direct selector returned no choice")
  let exact := value.generic == sample.expected.generic && value.sourceKeys == sample.expected.sourceKeys
  return Json.mkObj [("client",toJson client),("query",toJson ordinal),("nanos",toJson elapsed),
    ("sameOriginalChoiceKeys",toJson exact),("genericUnits",toJson value.generic.size),
    ("sourceKeys",toJson value.sourceKeys.size)]

def run (source fixture destination : System.FilePath) : IO Unit := do
  check (!(← destination.pathExists)) "preserve previous direct-selector diagnostic"
  IO.FS.createDirAll destination
  let cases ← IO.mkRef (#[] : Array Case)
  let record := fun (_choose : Bool) (expected : ServiceChoice) (query : ServiceQuery) (units : Array ServiceUnit)
      (pieces : List CuePiece) (source : Synapses.PreparedSourceView.Domain) => do
    cases.modify (·.push ⟨query,units,pieces,source,expected⟩)
    pure (some (Json.mkObj [("units",toJson units.size),("pieces",toJson pieces.length)]))
  SelectorStructure.runObserved record false source fixture (destination/"prepared.json")
  let cases ← cases.get
  check (cases.size == 3) "three unchanged source queries required"
  let mut serial := #[]
  for index in [:3] do
    let some sample := cases[index]? | throw (IO.userError "prepared case is absent")
    serial := serial.push (← solve sample index (index+1))
  check (serial.all (·.getObjValD "sameOriginalChoiceKeys" == toJson true)) "direct serial choices changed"
  let mut phases := #[]
  for count in [4,16] do
    let started ← IO.monoNanosNow
    let tasks ← (Array.range count).mapM fun client => do
      let some sample := cases[client%cases.size]? | throw (IO.userError "prepared parallel case is absent")
      IO.asTask (solve sample client (client%cases.size+1)) .dedicated
    let rows ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
    let wall := (← IO.monoNanosNow)-started
    let passed := rows.all (·.getObjValD "sameOriginalChoiceKeys" == toJson true)
    let phase := Json.mkObj [("clients",toJson count),("rows",toJson rows),("wallNanos",toJson wall),("passed",toJson passed)]
    phases := phases.push phase
    IO.FS.writeFile (destination/("phase-"++toString count++".json")) phase.compress
    check passed "parallel direct selector changed original choices"
  let prepared ← SelectorStructure.read (destination/"prepared.json")
  let before ← IO.ofExcept (prepared.getObjValAs? (Array (String × String)) "sourceFiles")
  check ((← SelectorStructure.sourceFiles source) == before) "pure diagnostic changed original source"
  IO.FS.writeFile (destination/"report.json") (Json.mkObj [("serial",toJson serial),("phases",toJson phases),
    ("originalSourceUnchanged",toJson true),("allChoicesExact",toJson true),
    ("unchangedSelectorOnly",toJson true),("actualHookOrFullCapacityClaim",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end BaseCueDirectChecks
def main (args : List String) : IO Unit := do
  let [source,fixture,destination] := args | throw (IO.userError "BaseCueDirectChecks SOURCE FIXTURE DESTINATION")
  BaseCueDirectChecks.run (.mk source) (.mk fixture) (.mk destination)
