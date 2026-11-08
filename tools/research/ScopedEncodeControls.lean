import tools.research.ReplayReadinessChecks
import tools.research.RealDeliveryProbe
import tools.research.ScopedEncodeMemo
open Lean Eggshell
namespace Eggshell.Research.ScopedEncodeControls
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def write (p : System.FilePath) (v : Json) : IO Unit := IO.FS.writeFile p v.compress
def normalized (v : Json) : Json := Json.mkObj [("vectors",v.getObjValD "vectors"),("coverage",v.getObjValD "coverage")]
def digest (v : Json) : String := Sha256.hex v.compress.toUTF8
def scope (n : Nat) : String := Sha256.hex s!"independent-project-scope:{n}".toUTF8
def key (n : Nat) : ScopedEncodeMemo.Key := ⟨scope 0,"same-numerical-contract",#[s!"payload-{n}"]⟩

run_elab do
  let environment ← Lean.getEnv
  for target in [``ScopedEncodeMemo.Store.lookup,``ScopedEncodeMemo.Store.remember] do
    let some body := (environment.find? target).bind (·.value?) | throwError "Missing immutable encoding memo operation"
    for forbidden in [``Std.Mutex.atomically,``Std.Mutex.tryAtomically,``ST.Ref.modify,``ST.Ref.modifyGet] do
      if body.getUsedConstants.contains forbidden then throwError "Encoding memo serializes or mutates a borrowed snapshot"
  let some body := (environment.find? ``Numerical.Backend.encode).bind (·.value?) |
    throwError "Missing actual numerical encode path"
  unless body.getUsedConstants.contains ``ScopedEncodeMemo.Store.lookup &&
    body.getUsedConstants.contains ``ScopedEncodeMemo.Store.remember &&
    body.getUsedConstants.contains ``Research.SharedEncoder.Server.request &&
    body.getUsedConstants.contains ``Numerical.Backend.model do
    throwError "Actual encoder bypasses the scoped memo or native ownership"

def pureControls : IO Json := do
  let item : ScopedEncodeMemo.Entry := ⟨key 0,"payload-0"⟩
  let memo := ScopedEncodeMemo.Memo.empty.insert item
  check (memo.lookup (key 0) == some "payload-0") "memo did not preserve the exact completed input"
  for foreignKey in #[{key 0 with scope := scope 1},{key 0 with contract := "foreign-contract"},key 1] do
    check ((memo.lookup foreignKey).isNone) "memo crossed scope, implementation or original text"
  let bounded := (List.range 100).foldl (fun found n => found.insert ⟨key n,s!"payload-{n}"⟩) ScopedEncodeMemo.Memo.empty
  check (bounded.entries.length == ScopedEncodeMemo.maxEntries &&
    (bounded.lookup (key 0)).isNone && bounded.lookup (key 99) == some "payload-99") "count eviction is not bounded/newest first"
  let big : ScopedEncodeMemo.Entry := ⟨key 999,String.ofList (List.replicate (ScopedEncodeMemo.maxBytes+1) 'x')⟩
  let after := bounded.insert big
  check (after.entries.length == bounded.entries.length && (after.lookup (key 99)).isSome &&
    (after.lookup (key 999)).isNone) "oversized entry changed the retained memo"
  let invalid := Json.mkObj [("vectors",toJson (#[1,2] : Array Nat)),("coverage",toJson (#[1] : Array Nat))]
  check ((ScopedEncodeMemo.completed? (key 0) invalid).isNone) "incomplete numerical result was memoized"
  let failing := invalid.setObjVal! "error" (toJson "cancelled")
  check ((ScopedEncodeMemo.completed? (key 0) failing).isNone) "failed numerical result was memoized"
  let native := Json.mkObj [("vectors",toJson (#[1] : Array Nat)),("coverage",toJson (#[1] : Array Nat)),
    ("id",toJson (7 : Nat)),("pid",toJson (9 : Nat)),("timing",toJson "foreign-clock")]
  let some completed := ScopedEncodeMemo.completed? (key 0) native | throw (IO.userError "complete numerical result refused")
  let payload ← IO.ofExcept (Json.parse completed.payload)
  check ((payload.getObjVal? "id").toOption.isNone && (payload.getObjVal? "pid").toOption.isNone &&
    (payload.getObjVal? "timing").toOption.isNone) "memo retained native ownership metadata"
  let store ← ScopedEncodeMemo.Store.make
  let tasks ← (Array.range 80).mapM fun n => IO.asTask (store.remember ⟨key n,s!"payload-{n}"⟩) .dedicated
  for task in tasks do discard <| IO.ofExcept (← IO.wait task)
  let state ← store.snapshot.get
  check (state.entries.length ≤ ScopedEncodeMemo.maxEntries &&
    ScopedEncodeMemo.weight state.entries ≤ ScopedEncodeMemo.maxBytes &&
    state.entries.all (fun entry => entry.key.scope == scope 0 && entry.payload == entry.key.texts[0]!))
    "racing immutable inserts changed a result or exceeded bounds"
  let storeMiss ← store.lookup {key 0 with scope := scope 1}
  check storeMiss.isNone "concurrent memo leaked a foreign project entry"
  let command := ["/fixed/runtime","search-provider"]
  let readScope := SemanticMatcher.encodingScope none [("source-a","authority-a")]
  check (readScope != SemanticMatcher.encodingScope none [("source-b","authority-a")] &&
    readScope != SemanticMatcher.encodingScope none [("source-a","authority-b")]) "project read domain scope lost identity or authority"
  let selected := SemanticMatcher.projectCommand command none (some readScope)
  check (selected == command++["--query-transient","--query-scope",readScope]) "read-only memo enabled persistent question storage"
  let options ← IO.ofExcept (SearchProvider.parse {cache := .mk "/unused",models := .mk "/unused"} selected.tail!.tail!)
  check (options.queryDatabase.isNone && options.queryScope == some readScope) "provider lost transient project scope"
  return Json.mkObj [("passed",toJson true),("racingInserts",toJson (80 : Nat)),
    ("retainedAfterRace",toJson state.entries.length),("bytesAfterRace",toJson (ScopedEncodeMemo.weight state.entries)),
    ("scopeContractOriginalTextIsolation",toJson true),("transientReadOnlyPreserved",toJson true),
    ("nativeOwnershipMetadataRemoved",toJson true),("oversizedAndIncompleteRejected",toJson true)]

def encode (client : Numerical.Client) (input : Json) (scopeId : Option String := none) : IO Json := do
  let input := scopeId.map (fun value => input.setObjVal! "scope" (toJson value)) |>.getD input
  let value ← IO.ofExcept (Json.parse (← client.request 69 input.compress))
  if let .ok error := value.getObjValAs? String "error" then throw (IO.userError error)
  return value
def stats (config : Numerical.Config) : IO Json := do
  let endpoint ← Numerical.resolve config
  IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats"))
def verify (expected : Array Json) (index : Nat) (reply : Json) : IO Unit :=
  check (expected[index]!.getObjValD "normalizedReplySha256" == toJson (digest (normalized reply)))
    "scoped memo changed the fixed numerical vectors/coverage"
def sample (index began : Nat) (value : Json) : IO Json := do
  return Json.mkObj [("input",toJson index),("elapsedMs",toJson ((← IO.monoMsNow)-began)),
    ("cacheHit",value.getObjValD "encodingCacheHit"),("digest",toJson (digest (normalized value))),
    ("trace",value.getObjValD "numericalTrace")]

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh scoped encoding control root required"
  IO.FS.createDirAll root
  check ((← Paths.dataRoot).normalize == (root/"private").normalize) "private numerical control scope changed"
  let structural ← pureControls
  write (root/"structure.json") structural
  let inputs ← IO.ofExcept (← read (project/"docs/candidates/shared-model/inputs.json")).getArr?
  let experiment := (← read (project/"docs/candidates/shared-model/controls.json")).getObjValD "experiment"
  let expected ← IO.ofExcept ((experiment.getObjValD "reference").getObjValAs? (Array Json) "observations")
  check (inputs.size == 17 && expected.size == 17) "fixed complete numerical control domain required"
  let assets := base/"prefix/share/eggshell/minilm"
  let config : Numerical.Config := ⟨MiniLM.model,assets/"models",assets/"fastembed-0.8.0/bin/python"⟩
  let keeper ← Numerical.keep config
  let client ← Numerical.openClient config
  try
    let mut original := #[]
    for index in [:17] do
      let began ← IO.monoMsNow
      let value ← encode client inputs[index]!
      verify expected index value
      check (value.getObjValD "encodingCacheHit" == toJson false) "unscoped request reused a private scope"
      original := original.push (← sample index began value)
    write (root/"original.json") (toJson original)
    let mut waves := #[]
    for (scopeId,wantHit) in #[(scope 0,false),(scope 0,true),(scope 1,false)] do
      let began ← IO.monoMsNow
      let mut rows := #[]
      for index in [:16] do
        let started ← IO.monoMsNow
        let value ← encode client inputs[index]! (some scopeId)
        verify expected index value
        check (value.getObjValD "encodingCacheHit" == toJson wantHit) "cold/hit/foreign scope changed its inference path"
        if wantHit then
          check ((value.getObjVal? "id").toOption.isNone && (value.getObjVal? "pid").toOption.isNone &&
            (value.getObjValD "timing").getObjValD "encodeUs" == toJson (0 : Nat)) "cache hit forged native ownership or inference time"
        rows := rows.push (← sample index started value)
      waves := waves.push (Json.mkObj [("scope",toJson scopeId),("expectedHit",toJson wantHit),
        ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("rows",toJson rows)])
      write (root/"waves.json") (toJson waves)
    let busyClients ← #[(),()].mapM fun _ => Numerical.openClient config
    let heavy ← busyClients.mapM fun busy => IO.asTask (encode busy inputs[16]!) .dedicated
    let bypass ← try
      let limit := (← IO.monoMsNow)+5000
      let mut before ← stats config
      while before.getObjValD "activeEncodes" != toJson (2 : Nat) do
        check ((← IO.monoMsNow) < limit) "two native compute slots never became active"
        IO.sleep 5
        before ← stats config
      let began ← IO.monoMsNow
      let hit ← encode client inputs[0]! (some (scope 1))
      let elapsed := (← IO.monoMsNow)-began
      verify expected 0 hit
      let after ← stats config
      check (hit.getObjValD "encodingCacheHit" == toJson true &&
        after.getObjValD "activeEncodes" == toJson (2 : Nat) && elapsed < 1000)
        "cached reply waited for occupied compute slots"
      pure (Json.mkObj [("passed",toJson true),("elapsedMs",toJson elapsed),
        ("activeBefore",before.getObjValD "activeEncodes"),("activeAfter",after.getObjValD "activeEncodes"),
        ("reply",← sample 0 began hit)])
    finally
      for task in heavy do discard <| IO.ofExcept (← IO.wait task)
      for busy in busyClients do busy.close
    let final ← stats config
    check (final.getObjValD "waitingEncodes" == toJson (0 : Nat) &&
      final.getObjValD "activeEncodes" == toJson (0 : Nat) &&
      final.getObjValD "modelCapacity" == toJson (1 : Nat) && final.getObjValD "computeCapacity" == toJson (2 : Nat))
      "memo changed numerical capacity or retained a borrower"
    write (root/"report.json") (Json.mkObj [("allPassed",toJson true),("structural",structural),
      ("original",toJson original),("waves",toJson waves),("hitWhileBothSlotsBusy",bypass),("finalStats",final),
      ("diagnosticOnly",toJson true),("fullHookOrEightyUsers",toJson false),("adopted",toJson false),
      ("answeringModelCalls",toJson (0 : Nat))])
  finally
    client.close
    Numerical.release keeper 10000
  check ((← Numerical.endpoint? config).isNone) "scoped numerical service endpoint survived shutdown"
  write (root/"shutdown.json") (Json.mkObj [("endpointRemoved",toJson true),("ownedServicesStopped",toJson true)])
end Eggshell.Research.ScopedEncodeControls
def main (args : List String) : IO UInt32 := do
  match args with
  | ["scoped-encode-controls",root] => Eggshell.Research.ScopedEncodeControls.run (.mk root); return 0
  | ["cells",_] | ["install-prefix",_] => scopedEncodeDeliveryMain args; return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
