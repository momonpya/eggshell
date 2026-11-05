import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.SearchInputChecks

#print axioms KeyedSearchProvider.Captured.accepts_exact
#print axioms KeyedSearchProvider.Captured.query_not_retained
#print axioms KeyedSearchProvider.Captured.changed_key_rejected
#print axioms PreparedReaders.Catalogue.bounded

run_meta do
  let environment ← getEnv
  for (name,required) in [
      (``federatedDiscovery,#[``PreparedReaders.Borrow.keyed,``KeyedSearchClient.nominate]),
      (``KeyedSearchClient.nominate,#[``BuiltinSearch.keyed,``KeyedProtocol.check,``KeyedProtocol.validateRelated]),
      (``KeyedSearchProvider.handle,#[``KeyedSearchProvider.Captured.use]),
      (``PreparedReaders.Borrow.keyed,#[``PreparedReaders.Reads.replay,``PreparedReaders.SnapshotImage.borrow,
        ``KeyedSearchProvider.Captured.borrow]),
      (``PreparedReaders.SearchInput.capture,#[``PreparedInputs.windows,``PreparedInputs.lexical,``PreparedInputs.numerical])] do
    let some value := (environment.find? name).bind (·.value?) | throwError "Missing input path {name}"
    for dependency in required do
      unless value.getUsedConstants.contains dependency do throwError "Prepared path {name} bypasses {dependency}"
  let some used := (environment.find? ``KeyedSearchProvider.Captured.use).bind (·.value?) |
    throwError "Missing captured provider use"
  for forbidden in #[``PreparedInputs.windows,``PreparedInputs.lexical,``PreparedInputs.numerical,
      ``KeyedProtocol.Scope.pin,``OwnerViews.restore] do
    unless !used.getUsedConstants.contains forbidden do throwError "Captured use reopens {forbidden}"

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := try let _ ← action; pure false catch _ => pure true
private def save (root : System.FilePath) (name : String) (value : Json) : IO Unit :=
  IO.FS.writeFile (root/name) value.pretty

def inspect (source root : System.FilePath) : IO Unit := do
  let project ← ProjectStore.openProject source
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let inputs ← view.sources.mapM fun original => do
    let some input ← PreparedInputs.load? original MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "original input not prepared")
    return input
  let some owners ← OwnerViews.load? view.sources | throw (IO.userError "owners not prepared")
  let pool ← PreparedReaders.Pool.new
  let began ← IO.monoNanosNow
  let borrow ← pool.acquire view.sources inputs (some owners)
  let buildNs := (← IO.monoNanosNow)-began
  let began ← IO.monoNanosNow
  let captured ← borrow.keyed view.sources inputs (some owners)
  let firstBorrowNs := (← IO.monoNanosNow)-began
  let request : KeyedProtocol.Request := ⟨"Return the recorded head and tail facts for support case-79.",
    view.sources.map KeyedProtocol.Scope.ofSnapshot,4096,8192,none,some inputs,some owners⟩
  check (captured.accepts request) "exact prepared request rejected"
  let badSource := {request with sources := request.sources.extract 1 request.sources.size}
  let reversed := {request with sources := request.sources.reverse}
  let omitted := {request with prepared := none}
  let altered := {request with prepared := some (inputs.map fun input => {input with model := "other-model"})}
  let producer := {request with prepared := some (inputs.map fun input => {input with producer := "other-producer"})}
  let wrongOwner := {request with owners := some {owners with sources := owners.sources.reverse}}
  for candidate in [badSource,reversed,omitted,altered,producer,wrongOwner] do
    check (!captured.accepts candidate) "changed complete input boundary accepted"
    check (← rejected (captured.use candidate MiniLM.model true)) "changed input reached captured execution"
  check (← rejected (captured.use request "other-model" true)) "changed model reached captured execution"
  check (← rejected (borrow.keyed (view.sources.extract 1 view.sources.size) inputs (some owners)))
    "changed source inventory reached borrowed provider"
  let privateInputs := inputs.map fun input => {input with usage := some input.source}
  let privateBorrow ← pool.acquire view.sources privateInputs (some owners)
  let other ← privateBorrow.keyed view.sources privateInputs (some owners)
  check (other.accepts {request with prepared := some privateInputs}) "private usage changed public eligibility"
  let statistics ← pool.stats
  check (statistics.getObjValD "builds" == toJson (1 : Nat) && statistics.getObjValD "hits" == toJson (1 : Nat))
    "public provider image rebuilt for a private usage change"
  let some first := captured.views[0]? >>= id | throw (IO.userError "first source is empty")
  let some second := other.views[0]? >>= id | throw (IO.userError "second source is empty")
  first.source.reads.set 777
  first.lexical.index.trace.set (some {})
  check ((← second.source.reads.get) == 0 && (← second.lexical.index.trace.get).isNone)
    "provider borrowers share original counters or index trace"
  let some (_,firstOwners) := captured.owners | throw (IO.userError "first owner image missing")
  let some (_,secondOwners) := other.owners | throw (IO.userError "second owner image missing")
  firstOwners.base.dictionary.reads.set 888
  check ((← secondOwners.base.dictionary.reads.get) == 0) "provider borrowers share owner counters"
  let some configured ← MiniLM.command (← Paths.installRoot) | throw (IO.userError "MiniLM unavailable")
  let command ← IO.ofExcept (KeyedSearchClient.command configured)
  let mut results := #[]
  for (query,index) in #[request.query,"Return the recorded head and tail facts for support case-0.",
      "Return the recorded support seed alpha and tail facts."].zipIdx do
    let request := {request with query}
    let mut expected : Option Json := none
    let order := if index == 1 then #[true,false] else #[false,true]
    for cached in order do
      let began ← IO.monoNanosNow
      let result ← BuiltinSearch.keyed command request (if cached then some captured else none)
      let elapsedNs := (← IO.monoNanosNow)-began
      if let .ok error := result.getObjValAs? String "error" then throw (IO.userError error)
      let decoded ← IO.ofExcept (fromJson? result : Except String KeyedProtocol.Response)
      let checked ← IO.ofExcept (KeyedProtocol.check view.sources decoded)
      KeyedProtocol.validateRelated view.sources checked
      if let some before := expected then check (result == before) "complete provider response changed"
      else expected := some result
      results := results.push (Json.mkObj [("query",toJson index),("cached",toJson cached),
        ("elapsedNs",toJson elapsedNs),("ranked",toJson checked.ranked.length),
        ("responseSha256",toJson (Sha256.hex result.compress.toUTF8))])
      save root "rows.json" (toJson results)
  for original in view.sources do
    check ((← PageMap.pin original.directory).head == original.head) "provider changed an original head"
  let report := Json.mkObj [("allPassed",toJson true),("sources",toJson view.sources.size),
    ("buildNs",toJson buildNs),("firstBorrowNs",toJson firstBorrowNs),("pool",statistics),
    ("timings",toJson results),("fullResponsesEqual",toJson true),("boundaryRejections",toJson (8 : Nat)),
    ("privateUsageDoesNotRebuildPublicInputs",toJson true),("borrowerStateIndependent",toJson true),
    ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  save root "report.json" report
  IO.println report.compress

def run (source root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve prior component inputs"
  IO.FS.createDirAll root
  Numerical.withDefaultKeeper (inspect source root) 1000

end Eggshell.Research.SearchInputChecks
