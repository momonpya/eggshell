import tools.research.ScopedEncodeControls
import tools.research.NumericalProtocolProbe
open Lean Eggshell
namespace Eggshell.Research.ScorePrepareControls
open NumericalProtocolProbe
def check := NumericalProtocolProbe.check
def read := NumericalProtocolProbe.read
def save := NumericalProtocolProbe.save
def hash := NumericalProtocolProbe.hash

#print axioms ProjectionCache.Hit.scope_exact
#print axioms ProjectionCache.Hit.key_exact
#print axioms ProjectionCache.Cached.foreign_scope_rejected
#print axioms ProjectionCache.Cached.foreign_key_rejected

-- Check the compiled consumer, rather than the spelling of the source patch.
run_elab do
  let environment ← getEnv
  let some body := (environment.find? ``Numerical.Backend.scoreBlocks).bind (·.value?) |
    throwError "Missing actual scoring consumer"
  unless body.getUsedConstants.contains ``BlockScore.prepare do
    throwError "Scoring bypasses checked frame preparation"
  let calls := body.find? fun expression => expression.isAppOf ``Std.Mutex.tryAtomically &&
    expression.getUsedConstants.contains ``BlockScore.prepare
  unless calls.isNone do throwError "Frame preparation still holds the scoring pipe"
  unless (body.find? fun expression => expression.isAppOf ``Std.Mutex.tryAtomically &&
      expression.getUsedConstants.contains ``Numerical.exchangeRaw).isSome do
    throwError "Raw scoring exchange lost exclusive pipe ownership"

def stats (config : Numerical.Config) : IO Json := do
  IO.ofExcept (Json.parse (← Plugin.Daemon.exchange (← Numerical.resolve config) "stats"))

def counts (value : Json) (expected : Nat) : IO Unit := do
  let hits ← IO.ofExcept (value.getObjValAs? Nat "projectionHits")
  let misses ← IO.ofExcept (value.getObjValAs? Nat "projectionMisses")
  check (hits+misses == expected) "frame counted another request's cache events"

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh score preparation control root required"
  IO.FS.createDirAll root
  let (rows,frozen) ← inputs
  let questions ← questions
  let some config ← Numerical.defaultConfig? | throw (IO.userError "MiniLM unavailable")
  let keeper ← Numerical.keep config
  try
    let endpoint ← Numerical.resolve config
    let client ← Numerical.openClient config
    try
      let encoded ← IO.ofExcept (Json.parse (← client.request 69 (queryBody questions[0]!).compress))
      let projections ← projectQuery encoded
      let batch := rows.extract 0 256
      let request := Json.mkObj [("queries",toJson projections),("blockRows",toJson batch)]
      let score := do
        let (value,profile) ← exchangeObserved endpoint "blocks" request.compress ((← IO.monoMsNow)+24000)
        counts value batch.size
        return (value,profile)
      let (cold,coldProfile) ← score
      let start ← IO.Promise.new
      let tasks ← (Array.range 16).mapM fun _ => IO.asTask (do
        discard <| IO.wait start.result!
        score) .dedicated
      let began ← IO.monoMsNow
      start.resolve ()
      let concurrent ← try tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
        finally
          for task in tasks do IO.cancel task
          for task in tasks do discard <| IO.wait task
      let elapsed := (← IO.monoMsNow)-began
      for (value,_) in concurrent do
        check (value.getObjValD "scores" == cold.getObjValD "scores" &&
          value.getObjValD "coverage" == cold.getObjValD "coverage") "parallel preparation changed numerical results"
      let before ← stats config
      let some first := rows[0]? | throw (IO.userError "fixed projection domain is empty")
      let bad := match first with
        | .indexed owner _ => BlockScore.Input.indexed owner (String.ofList (List.replicate 64 '0'))
        | .projected _ => first
      let badRequest := Json.mkObj [("queries",toJson projections),("blockRows",toJson #[bad])]
      let failed ← try
        discard <| exchangeObserved endpoint "blocks" badRequest.compress ((← IO.monoMsNow)+24000)
        pure false
        catch _ => pure true
      check failed "missing projection was not rejected"
      let (afterBad,_) ← score
      let after ← stats config
      check (before.getObjValD "rawPid" != Json.null && afterBad.getObjValD "scores" == cold.getObjValD "scores" &&
        before.getObjValD "rawPid" == after.getObjValD "rawPid" &&
        before.getObjValD "rawStarts" == after.getObjValD "rawStarts")
        "request-local storage failure retired a healthy numerical pipe"
      let cache ← ProjectionCache.Cache.make
      let pages ← IO.mkRef ({} : DB.PageMap.PageCache)
      let expired ← try
        discard <| BlockScore.prepare config.model cache pages request.compress 0 (pure false)
        pure false
        catch _ => pure true
      let cancelled ← try
        discard <| BlockScore.prepare config.model cache pages request.compress ((← IO.monoMsNow)+24000) (pure true)
        pure false
        catch _ => pure true
      check (expired && cancelled && (← cache.state.get).entries.isEmpty)
        "expired or cancelled preparation touched projection storage"
      let profiles ← IO.mkRef (#[] : Array Json)
      let full ← scorePass endpoint projections rows ((← IO.monoMsNow)+24000) profiles
      let fullAgain ← scorePass endpoint projections rows ((← IO.monoMsNow)+24000) profiles
      check (full == fullAgain && full.size == 1933) "full exact score order changed"
      let prior ← read (Research.ScopedEncodeControls.project/"docs/candidates/local-completion/protocol-16.json")
      let referenceRows ← IO.ofExcept (prior.getObjValAs? (Array Json) "references")
      check (referenceRows.size == 3) "missing fixed original numerical references"
      check (prior.getObjValD "frozen" == (frozen.setObjVal! "questions" (toJson questions)
        |>.setObjVal! "inputSha256" (toJson (← hash fixedInput)))) "reference DB/questions/row order changed"
      let mut references := #[]
      for index in [:questions.size] do
        let result ← query config rows questions[index]! index (index+1)
        check (result.getObjValD "completed" == toJson true &&
          result.getObjValD "scoreSha256" == referenceRows[index]!.getObjValD "scoreSha256" &&
          result.getObjValD "encodingSha256" == referenceRows[index]!.getObjValD "encodingSha256")
          "actual indexed scores or query vectors differ from original complete numerical reference"
        references := references.push result
      for profile in ← profiles.get do
        let count ← IO.ofExcept (profile.getObjValAs? Nat "rows")
        -- The response-only counters were checked above under simultaneous load.
        check (count > 0 && count ≤ 256) "full-domain batch bounds changed"
      verifyHeads frozen
      save (root/"report.json") (Json.mkObj [("allPassed",toJson true),("diagnosticOnly",toJson true),
        ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),("indexedRows",toJson rows.size),
        ("parallelFrames",toJson (16 : Nat)),("parallelWallMs",toJson elapsed),
        ("cold",cold),("coldProfile",coldProfile),("concurrent",toJson concurrent),
        ("allFrameCountersExact",toJson true),("invalidStorageRequestLocal",toJson true),
        ("expiredAndCancelledBeforeStorage",toJson true),("beforeFailure",before),("afterFailure",after),
        ("fullScoreSha256",toJson (Sha256.hex (toJson full).compress.toUTF8)),
        ("allThreeOriginalNumericalReferencesEqual",toJson true),("references",toJson references),
        ("fullCoverageAndRepeatedScoresEqual",toJson true),("fullProfiles",toJson (← profiles.get)),
        ("originalHeadsUnchanged",toJson true)])
    finally client.close
  finally Numerical.release keeper 10000
  check ((← Numerical.endpoint? config).isNone) "numerical endpoint survived shutdown"
  save (root/"shutdown.json") (Json.mkObj [("endpointRemoved",toJson true),("ownedServicesStopped",toJson true)])
end Eggshell.Research.ScorePrepareControls
def main (args : List String) : IO UInt32 := do
  match args with
  | ["score-prepare-controls",root] => Eggshell.Research.ScorePrepareControls.run (.mk root); return 0
  | ["cells",_] | ["install-prefix",_] => scopedEncodeDeliveryMain args; return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
