import tools.research.StudyAcquire
open Lean Eggshell
namespace Eggshell.Research.StudyProfileChecks
#print axioms StudyProfile.checked_preserves_value
#print axioms StudyAdmission.candidate_measurement_requires_target
def run (directory seedPrototype : String) : IO Unit := do
  let root := System.FilePath.mk directory
  unless !(← root.pathExists) do throw (IO.userError "preserve budget-transfer checks")
  IO.FS.createDirAll root
  let prototype ← StudyAdmission.readJson seedPrototype
  unless (fromJson? (α := StudyAcquire.Plan) prototype).toOption.isNone do
    throw (IO.userError "an acquisition without an explicit envelope was accepted")
  unless (StudyProfile.checked 0).toOption.isNone do throw (IO.userError "zero envelope was accepted")
  let miss := Json.mkObj [("availableDelivery",Json.mkObj [("targetMet",toJson false)])]
  unless decide (StudyAdmission.mayMeasure .reference miss) && !(decide (StudyAdmission.mayMeasure .candidate miss)) do
    throw (IO.userError "reference measurement bypassed the candidate delivery gate")
  let mut checked := #[]
  for chars in #[1,120000,500000] do
    let plan ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (prototype.setObjVal! "handoffChars" (toJson chars)))
    let roundTrip ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (toJson plan))
    unless plan.handoffChars == chars && roundTrip.handoffChars == chars do
      throw (IO.userError "sealed envelope changed in plan transport")
    for write in [false,true] do
      let config := root / s!"{chars}-{write}.toml"
      IO.FS.writeFile config (StudyProfile.render "/runtime with spaces/eggshell" "/db/記憶.egg"
        (← IO.ofExcept (StudyProfile.checked roundTrip.handoffChars)) write)
      let parsed ← Config.parseFile config
      let selected ← IO.ofExcept (Config.resolve parsed "work")
      unless selected.handoffChars == chars && selected.read.map (·.path.toString) == ["/db/記憶.egg"] &&
          selected.write.map (·.path.toString) == (if write then some "/db/記憶.egg" else none) &&
          selected.semanticMatcher == some ["/runtime with spaces/eggshell","search-provider"] do
        throw (IO.userError "native profile changed the explicit arm treatment")
      checked := checked.push (chars,write,selected.handoffChars)
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("profiles",toJson checked),
    ("missingEnvelopeRejected",toJson true),("zeroEnvelopeRejected",toJson true),
    ("candidateMissRejected",toJson true),("referenceMissRecorded",toJson true),
    ("modelCalls",toJson (0 : Nat))]).pretty
end Eggshell.Research.StudyProfileChecks
