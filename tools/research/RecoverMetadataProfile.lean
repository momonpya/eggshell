import tools.research.NativeTrialAudit
import tools.research.StudyRuntime
open Lean Eggshell Eggshell.Research
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def frame? (line : String) : Option (String × Nat) := do
  let words := ((line.splitOn " ").filter (!·.isEmpty)).dropWhile fun word => word.toNat?.isNone
  let count ← words[0]?.bind String.toNat?
  let symbol ← words[1]?
  unless symbol.startsWith "l_" || symbol.startsWith "lean_" do none
  return (symbol,count)

private def summarize (path : System.FilePath) : IO Json := do
  check ((← path.metadata).byteSize < 8*1024*1024) "native sample exceeds diagnostic bound"
  let text ← IO.FS.readFile path
  let mut counts : Std.HashMap String Nat := {}
  for line in text.splitOn "\n" do
    if let some (name,count) := frame? line then counts := counts.insert name (max count (counts[name]?.getD 0))
  let ordered := counts.toArray.qsort fun a b => if a.2 == b.2 then a.1 < b.1 else b.2 < a.2
  let tops := (text.splitOn "Sort by top of stack, same collapsed (when >= 5):\n")[1]?.getD ""
  let tops := ((tops.splitOn "\n\n").headD "").splitOn "\n"
  return Json.mkObj [("sha256",toJson (Sha256.hex text.toUTF8)),("bytes",toJson text.utf8ByteSize),
    ("headers",toJson ((text.splitOn "\n").take 23)),("maximumInclusiveSamplesByCallPath",toJson (ordered.extract 0 240)),
    ("symbols",toJson counts.size),("retainedSymbols",toJson (min 240 counts.size)),
    ("topOfStack",toJson tops),
    ("interpretation",toJson "Inclusive path counts overlap across functions and threads. They are not direct function wall times or whole-hook CPU percentages.")]

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let records := project / "docs/candidates/metadata-profile"
  let directory := records / "hooks/candidate/rep-0/topic-1"
  check (!(← (records / "result.json").pathExists)) "preserve the recovered completed hook"
  let guard ← read (records / "run.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (1 : Nat) &&
    guard.getObjValD "guardTriggered" == toJson false && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "actual observation differs from the recorded controller error"
  let receipt ← read (directory / "UserPromptSubmit/record.json")
  let stdout ← IO.FS.readFile (directory / "UserPromptSubmit/stdout")
  check (receipt.getObjValD "exitCode" == toJson (0 : Nat) &&
    receipt.getObjValD "stdoutSha256" == toJson (Sha256.hex stdout.toUTF8)) "completed hook receipt changed"
  let reply ← IO.ofExcept (Json.parse stdout)
  let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
  let sha := Sha256.hex body.toUTF8
  let described ← read (records / "hooks/candidate-runtime.json")
  let runtime := described.getObjValD "runtime"
  check (runtime.getObjValD "sha256" == toJson (← ArtifactHash.hex (study / "shared-snapshot/project-metadata-runtime-build/StudyMain")))
    "current product changed"
  let sourceFiles ← StudyRuntime.files (study / "r0/stage1/history/source.egg")
  check ((← StudyRuntime.files (study / "shared-snapshot/metadata-profile-trial/candidate/work.egg")) == sourceFiles)
    "the diagnostic source differs"
  IO.FS.writeFile (directory / "body.txt") body
  IO.FS.writeFile (directory / "before-gold.json") (Json.mkObj [("bodySha256",toJson sha),
    ("sourceFiles",toJson sourceFiles),("runtime",runtime),("goldRead",toJson false),
    ("recoveredFromCompletedCommand",toJson true)]).pretty
  let frozenEntries ← IO.ofExcept ((← read (project /
    "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let some frozen := frozenEntries[0]? | throw (IO.userError "missing frozen topic")
  check (frozen.getObjValD "topic" == toJson (1 : Nat) &&
    (frozen.getObjValD "specification").getObjValD "files" == toJson sourceFiles)
    "recovery changed the frozen evidence domain"
  let audit ← NativeTrialAudit.replayAvailable (frozen.getObjValD "specification") (directory / "body.txt").toString sha
  check (audit.getObjValD "availableEvidence" == frozen.getObjValD "available") "recovery changed the denominator"
  let reference := project / "docs/candidates/source-plan/bodies/topic-1.txt"
  check ((← IO.FS.readFile reference) == body) "profile changed the parent's actual body"
  let profile ← summarize (directory / "native-profile/publisher.sample.txt")
  let sampleReceipt ← read (directory / "native-profile/publisher.sample.json")
  check (sampleReceipt.getObjValD "exitCode" == toJson (0 : Nat)) "publisher sample did not finish"
  IO.FS.writeFile (records / "publisher-profile.json") (Json.mkObj [("sample",profile),("receipt",sampleReceipt)]).pretty
  let mut closed := #[]
  for path in [directory / "shutdown.json",directory / "publisher-shutdown.json",records / "hooks/candidate/prepare-shutdown.json"] do
    let report ← read path
    check (["acknowledged","processExited","endpointRemoved"].all (fun key => report.getObjValD key == toJson true))
      "profile service did not close"
    closed := closed.push report
  IO.FS.writeFile (records / "shutdowns.json") (toJson closed).pretty
  IO.FS.writeFile (records / "runtime.json") described.pretty
  IO.FS.writeFile (records / "result.json") (Json.mkObj [("runtime",runtime),
    ("elapsedMs",receipt.getObjValD "elapsedMs"),("topic",toJson (1 : Nat)),("bodySha256",toJson sha),
    ("sameParentBody",toJson true),("bodyReference",toJson reference.toString),("beforeGold",← read (directory / "before-gold.json")),
    ("nativeDeliveryAudit",audit),("availableDelivery",audit.getObjValD "availableDelivery"),
    ("actualHookCount",toJson (1 : Nat)),("publisherProfileCaptured",toJson true),("workerProfileCaptured",toJson false),
    ("outerControllerExitCode",toJson (1 : Nat)),("completedHookExitCode",toJson (0 : Nat)),
    ("hookReexecuted",toJson false),("answeringModelCalls",toJson (0 : Nat)),("newSeeds",toJson (0 : Nat)),
    ("latencyComparisonMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.println (Json.mkObj [("elapsedMs",receipt.getObjValD "elapsedMs"),
    ("availableDelivery",audit.getObjValD "availableDelivery"),("publisherProfileCaptured",toJson true),
    ("workerProfileCaptured",toJson false),("hookReexecuted",toJson false)]).compress
