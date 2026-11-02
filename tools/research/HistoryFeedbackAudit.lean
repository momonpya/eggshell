import tools.research.StudyHistoryChecks

#print axioms Eggshell.Research.StudyHistory.kept_family
#print axioms Eggshell.Research.StudyHistory.feedback_family_is_content_addressed

open Lean Eggshell Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

/-- Audit actual acquired events and classifier data through the same freeze
and fork functions used by the comparison harness. No warm or model call. -/
private def actual (source data sealedHistory target : System.FilePath) : IO Unit := do
  check (target.isAbsolute && !(← target.pathExists)) "new absolute audit root required"
  let sourceBefore ← StudyRuntime.files source
  let sourceHead ← DB.PageMap.pin source
  let privateRoot := data / "read-cache" / sourceHead.head.identity / "synapses"
  let privateBefore ← StudyAdmission.tree privateRoot
  let sealedBefore ← ArtifactHash.hex sealedHistory
  let old ← IO.ofExcept (fromJson? (α := StudyHistory.Snapshot)
    (← StudyAdmission.readJson sealedHistory.toString))
  FileSystem.privateDirectory target
  let common ← StudyHistory.freeze source data (target / "common")
  let manifest := target / "common/history.json"
  let artifact : StudyAdmission.Artifact := ⟨manifest.toString,← ArtifactHash.hex manifest⟩
  let current ← StudyHistory.fork artifact (target / "current")
  let candidate ← StudyHistory.fork artifact (target / "candidate")
  check (toJson current == toJson common && toJson candidate == toJson common)
    "forked histories differ from the common private input"
  let mut feedback := #[]
  let mut omitted := #[]
  for family in common.privateFamilies do
    let some parsed := StudyHistory.feedbackFamily? family.name | continue
    let original ← DB.PageMap.pin (privateRoot / family.name)
    let facts ← Synapses.Index.allFacts original
    check (facts.all (fun fact => match fact with | .used _ => true | _ => false))
      "shared facts entered a private feedback family"
    for arm in ["current","candidate"] do
      let path := target / arm / "data/read-cache" / common.database / "synapses" / family.name
      let copied ← DB.PageMap.pin path
      check (copied.head == original.head && (← Synapses.Index.allFacts copied) == facts)
        "copied feedback facts or their exact index head changed"
    feedback := feedback.push (Json.mkObj [("family",toJson family.name),
      ("classifier",toJson parsed.classifier),("facts",toJson facts.size),
      ("head",toJson original.head),("files",toJson family.files)])
    if !old.privateFamilies.any (·.name == family.name) then omitted := omitted.push family.name
  check (!feedback.isEmpty) "actual acquired classifier feedback is missing"
  check ((← StudyRuntime.files source) == sourceBefore &&
    (← StudyAdmission.tree privateRoot) == privateBefore && (← ArtifactHash.hex sealedHistory) == sealedBefore)
    "actual audit changed the original source, private history or sealed earlier manifest"
  let report := Json.mkObj [("source",toJson source.toString),("sourceFiles",toJson sourceBefore),
    ("sealedHistory",toJson sealedHistory.toString),("sealedHistorySha256",toJson sealedBefore),
    ("sealedHistoryFamilies",toJson (old.privateFamilies.map (·.name))),
    ("feedback",toJson feedback),("omittedInSealedHistory",toJson omitted),
    ("sourceAndPrivateInputsUnchanged",toJson true),("identicalFactsInBothArms",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("warmPerformed",toJson false),
    ("tokenImprovementMeasured",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (target / "result.json") report.pretty
  IO.println report.compress

def main (args : List String) : IO Unit := do
  match args with
  | ["checks",directory] => StudyHistoryChecks.cliMain [directory]
  | ["actual",source,data,sealedHistory,target] => actual (.mk source) (.mk data) (.mk sealedHistory) (.mk target)
  | _ => throw (IO.userError "checks NEW-ROOT | actual SOURCE PRIVATE-DATA SEALED-HISTORY NEW-ROOT")
