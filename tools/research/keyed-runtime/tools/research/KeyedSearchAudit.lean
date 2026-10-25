import Eggshell.KeyedSearchProvider
import Eggshell.KeyedSearchClient
import Eggshell.PluginModel
import Lean

open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def failed (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

open Lean in
run_meta do
  for name in #[``KeyedProtocol.scoped_choice_in_original_array,
      ``KeyedSearchProvider.originalOwners_compiled,
      ``VectorRoute.prepared_preserves_original, ``VectorRoute.nomination_keys_bounded,
      ``WindowOwners.entries_original] do
    for dependency in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains dependency do
        throwError "Unapproved keyed search dependency: {name}, {dependency}"
  logInfo "Closed original sources and original vector/window invariants checked"

private def outcome (index : Nat) : IO Value :=
  IO.ofExcept (Plugin.relation? .outcome [
    .semantic (.text s!"timer scheduling question {index}"),
    .semantic (.text (s!"original timer scheduling observation {index} " ++ String.ofList (List.replicate 700 'x')))])

private def publish (source : Snapshot) (values : List Value) : IO Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let roots ← values.mapM intern.root
    writeChange writer ⟨roots,[],false⟩
  PageMap.pin source.directory

private def routeFixture (output : System.FilePath) : IO Json := do
  let model := "keyed-fixture"
  let encoder := "fixed-exact-bits"
  let root := output / "vectors"
  FileSystem.privateDirectory root
  let keys := (List.range 65).map fun index => Sha256.hex s!"route-original-{index}".toUTF8
  let _ ← VectorMatrix.ensureUsing root model encoder keys fun key => pure ⟨key,"fixture","000000000000f03f"⟩
  let some first ← VectorMatrix.open? root model encoder | throw (IO.userError "fixture matrix missing")
  let initial ← VectorRoute.refresh root model encoder first
  let some route ← VectorRoute.open? root model encoder first | throw (IO.userError "initial router missing")
  let unchanged ← VectorRoute.refresh root model encoder first
  check (initial.mode == "replaced" && unchanged.mode == "warm" && unchanged.writtenBytes == 0)
    "unchanged routing was rebuilt"
  let point ← VectorRoute.readPoint first keys.head!
  let extra := Sha256.hex "later original".toUTF8
  let _ ← VectorMatrix.ensureUsing root model encoder [extra] fun key => pure ⟨key,"fixture","0000000000000040"⟩
  let some second ← VectorMatrix.open? root model encoder | throw (IO.userError "new matrix missing")
  check ((← VectorRoute.open? root model encoder second).isNone) "old router silently omitted a new matrix row"
  let updated ← VectorRoute.refresh root model encoder second
  let some newer ← VectorRoute.open? root model encoder second | throw (IO.userError "router replacement missing")
  let before ← VectorRoute.nominate route point 128
  let after ← VectorRoute.nominate newer point 128
  check (before.val.keys.mergeSort == keys.mergeSort && after.val.keys.mergeSort == (extra::keys).mergeSort &&
    updated.points == 66) "replacement changed pinned originals or lost the appended point"
  return Json.mkObj [("originalPoints",toJson keys.length),("updatedPoints",toJson updated.points),
    ("idempotent",toJson true),("changedMatrixUnavailableUntilReplacement",toJson true),
    ("oldPinnedOriginalsPreserved",toJson true)]

private def scenario (output : System.FilePath) : IO Json := do
  let empty ← PageMap.create (output / "empty.egg") (Persistence.valueToJson (.text "fixture-authority")).compress
  let some emptyResult ← KeyedSearchClient.nominate ["/missing-provider"] #[empty] "nothing saved" |
    throw (IO.userError "empty source tried to start a numerical provider")
  check (emptyResult.related.isEmpty && emptyResult.ranked.isEmpty) "empty source invented history"
  let values ← (List.range 8).mapM outcome
  let first ← publish empty values
  let other ← PageMap.create (output / "other.egg") first.head.authority
  let second ← publish other values
  for source in #[first,second] do
    let _ ← WindowOwners.refresh source .user
    let _ ← RetrievalResearch.Index.warm source .user
  let sources := #[first,second]
  let request : KeyedProtocol.Request := ⟨"timer scheduling",sources.map KeyedProtocol.Scope.ofSnapshot,128,8192,none⟩
  let options : SearchProvider.Options := {cache := output / "queries",models := .mk "unused",mode := "lexical"}
  let raw ← KeyedSearchProvider.handle options none request
  let response ← IO.ofExcept (fromJson? raw : Except String KeyedProtocol.Response)
  let checked ← IO.ofExcept (KeyedProtocol.check sources response)
  KeyedProtocol.validateRelated sources checked
  check (response.related.length > 0 && response.coverage.length == 2 &&
    checked.related.any (·.source.val == 0) && checked.related.any (·.source.val == 1))
    "equal local IDs from two DBs were collapsed or omitted"
  let some original := response.ranked.head? | throw (IO.userError "fixture needs an original choice")
  let firstKey := Sha256.hex "position five".toUTF8
  let laterKey := Sha256.hex "position seventeen".toUTF8
  let compact := {original with windows := [⟨5,firstKey⟩,⟨17,laterKey⟩]}
  let (projected,selected) ← IO.ofExcept (KeyedSearchProvider.project #[compact]
    ⟨[0],[0],[⟨0,[1]⟩]⟩)
  check (selected == [0] && projected == [{compact with windows := [⟨17,laterKey⟩]}])
    "score-local ordinal replaced the original window position"
  let some document := (← searchDocuments first).head? | throw (IO.userError "original fixture empty")
  let some later := document.windows[1]? | throw (IO.userError "fixture needs a nonzero original window")
  let ordinal ← getNat first.get (key "member" document.owner)
  let originalPosition : KeyedProtocol.Choice := ⟨0,document.owner,document.work,ordinal,[⟨1,later⟩]⟩
  KeyedProtocol.validateRelated sources (← IO.ofExcept (KeyedProtocol.check sources
    {response with ranked := [originalPosition],related := [0]}))
  let rejected := fun value => (KeyedProtocol.check sources value).toOption.isNone
  check (rejected {response with ranked := [{original with source := 2}],related := [0]})
    "foreign response source accepted"
  check (rejected {response with ranked := [original,original],related := [0]}) "duplicate scoped owner accepted"
  check (rejected {response with related := [response.ranked.length]}) "foreign ranked position accepted"
  let key := Sha256.hex "invented".toUTF8
  check (rejected {response with ranked := [{original with windows := [⟨0,key⟩,⟨0,key⟩]}],related := [0]})
    "duplicate original window position accepted"
  check (rejected {response with ranked := [{original with windows := [⟨0,"not-a-window"⟩]}],related := [0]})
    "invalid original window digest accepted"
  let forged ← IO.ofExcept (KeyedProtocol.check sources
    {response with ranked := [{original with work := original.work+10000}],related := [0]})
  check (← failed (KeyedProtocol.validateRelated sources forged)) "cache hint invented original Work authority"
  let forgedWindow ← IO.ofExcept (KeyedProtocol.check sources
    {response with ranked := [{original with windows := [⟨10000,key⟩]}],related := [0]})
  check (← failed (KeyedProtocol.validateRelated sources forgedWindow)) "foreign source window reached admission"
  let foreign := {KeyedProtocol.Scope.ofSnapshot first with head := second.head}
  check (← failed foreign.pin) "foreign source head accepted"
  let appended ← publish first [← outcome 9]
  let pinned ← (KeyedProtocol.Scope.ofSnapshot first).pin
  check (pinned.head == first.head && appended.head != first.head) "concurrent suffix changed the requested root"
  let cold ← publish (← PageMap.create (output / "cold.egg") first.head.authority) [← outcome 20]
  let coldRequest : KeyedProtocol.Request := ⟨"timer",#[KeyedProtocol.Scope.ofSnapshot cold],128,8192,none⟩
  check (← failed (KeyedSearchProvider.handle options none coldRequest)) "cold source became a completed empty search"
  let routes ← routeFixture output
  return Json.mkObj [("sourceCount",toJson 2),("related",toJson response.related.length),
    ("ranked",toJson response.ranked.length),("emptyDoesNotStartProvider",toJson true),
    ("sameLocalIdsKeepDbScope",toJson true),("foreignSourceAndRankRejected",toJson true),
    ("originalWorkAndPositionChecked",toJson true),("compactPositionsRestored",toJson true),
    ("nonzeroOriginalPositionValidated",toJson true),("oldPinnedScopeRetained",toJson true),
    ("coldIsUnavailable",toJson true),("routing",routes),
    ("scope",toJson "component lexical wire and exact-bit routing fixtures; no answering model or source embeddings")]

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "KeyedSearchAudit NEW-OUTPUT")
  let output := System.FilePath.mk path
  check (!(← output.pathExists)) "preserve earlier audit"
  FileSystem.privateDirectory output
  let result ← scenario output
  IO.FS.writeFile (output / "result.json") result.pretty
  IO.println result.compress
