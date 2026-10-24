import Eggshell.WorkClassLookup
open Lean Eggshell Eggshell.Persistence.Store Eggshell.WorkClassLookup

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def edge (left right : Value) (localScope : Bool := false) : IO UnionEdge := do
  if same : Value.sameExactFootprint left right then
    pure ⟨left,right,if localScope then .run (.text "class-query") else .workspace (.text "class-fixture"),
      Value.sameExactFootprint_sound same⟩
  else throw (IO.userError "invalid test Union")

private def owner (work body : String) : OutcomeEdge :=
  OutcomeEdge.make (.text work) (.text body) [] (by simp) (by simp)

private def makeFixture (path : System.FilePath) (extra : Bool) : IO Unit := do
  check (!(← path.pathExists)) "preserve prior fixture"
  let source ← DB.PageMap.create path (Persistence.valueToJson (.text "class-fixture")).compress
  let alpha := Value.text "alpha"
  let beta := Value.text "beta"
  let first := Value.applyList .all [.semantic alpha]
  let second := Value.applyList .all [.semantic beta]
  let unions ← [edge alpha beta,edge first (.text "gamma"),edge second (.text "delta")].mapM id
  let owners := if extra then [owner "alpha" "SECOND_DATABASE"] else
    [owner "alpha" "ALPHA_ONE",owner "alpha" "ALPHA_TWO",owner "beta" "BETA",
      owner "gamma" "GAMMA",owner "delta" "DELTA",owner "other" "UNRELATED"]
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← owners.mapM (fun item => intern.root item.relation)
    addUnions intern unions
    writeChange writer ⟨ids,[],true⟩
  pure ()

private def generators (snapshot : DB.PageMap.Snapshot) : IO (List UnionEdge) := do
  let reader ← NodeReader.new snapshot
  pure ((← reader.unions (← authority snapshot)).map (·.edge))

private def prepared (persistent localEdges : List UnionEdge) : IO (Prepared persistent localEdges) :=
  match prepare? persistent localEdges with
  | some result => pure result
  | none => throw (IO.userError "class preparation failed")

private def oracleRows (snapshot : DB.PageMap.Snapshot) : IO (List (Nat × Value)) := do
  let rows ← directory snapshot "searchCandidate"
  check (rows.length == (← getNat snapshot.get "candidates")) "incomplete oracle owners"
  let reader ← NodeReader.new snapshot
  rows.mapM fun (ordinal,id) => do
    let original ← reader.workOrigin (← reader.locateOutcome id)
    pure (ordinal,original.work)

private def fullOracle (roots : List Value) (persistent localEdges : List UnionEdge) :
    IO (QuotientBuilder.CongruenceSound.Checked roots persistent localEdges) :=
  match QuotientBuilder.CongruenceSound.attach roots persistent localEdges
      (QuotientBuilder.build? roots persistent localEdges) rfl with
  | some result => pure result
  | none => throw (IO.userError "complete oracle quotient failed")

private def queryCheck (snapshot : DB.PageMap.Snapshot) (persistent localEdges : List UnionEdge)
    (query : String) (expected : List String) : IO Unit := do
  let classes ← prepared persistent localEdges
  let reader ← NodeReader.new snapshot
  let found ← reader.classOwners classes query.toUTF8
  let bodies := found.map fun item => match item.edge.outcome with
    | .atom bytes => (String.fromUTF8? bytes).getD ""
    | _ => "nontext"
  check (bodies == expected) s!"wrong owners for {query}: {bodies}"
  let originals ← oracleRows snapshot
  let full ← fullOracle (originals.map Prod.snd) persistent localEdges
  let reference := originals.filter fun row => full.quotient.toEquality.same (.text query) row.2
  check (found.map (·.ordinal) == reference.map Prod.fst) "class owner order differs from full scan"

private def small (folder : System.FilePath) : IO Unit := do
  check (!(← folder.pathExists)) "preserve prior small test"
  FileSystem.privateDirectory folder
  let one := folder / "one.egg"
  let two := folder / "two.egg"
  makeFixture one false
  makeFixture two true
  let snapshot ← DB.PageMap.pin one
  let unions ← generators snapshot
  queryCheck snapshot unions [] "alpha" ["ALPHA_ONE","ALPHA_TWO","BETA"]
  queryCheck snapshot unions [] "gamma" ["GAMMA","DELTA"]
  queryCheck snapshot unions [] "other" ["UNRELATED"]
  queryCheck snapshot unions [] "absent" []
  let localEdge ← edge (.text "temporary") (.text "alpha") true
  queryCheck snapshot unions [localEdge] "temporary" ["ALPHA_ONE","ALPHA_TWO","BETA"]
  queryCheck snapshot unions [] "temporary" []
  queryCheck snapshot [] [] "alpha" ["ALPHA_ONE","ALPHA_TWO"]
  queryCheck snapshot [] [] "gamma" ["GAMMA"]
  let exactA := Value.applyList .receipt [.exact (.text "fingerprint-A"),.semantic (.text "alpha")]
  let exactB := Value.applyList .receipt [.exact (.text "fingerprint-B"),.semantic (.text "beta")]
  let checked ← fullOracle [exactA,exactB] unions []
  check (!checked.quotient.toEquality.same exactA exactB) "Exact fingerprint barrier collapsed"
  let sources := #[snapshot,← DB.PageMap.pin two]
  let readers ← NodeReaders.new sources
  let classes ← prepared unions []
  let both ← readers.classOwners classes "alpha".toUTF8
  check (both.map (·.1.val) == [0,0,0,1]) "source identity/order lost"
  check (both.map (fun row => row.2.ordinal) == [0,1,2,0]) "source-local ordinals collapsed"
  let none ← readers.classOwners classes "absent".toUTF8
  check none.isEmpty "federated negative query invented an owner"
  -- Retire an actual owner. The prior pinned snapshot still has its own
  -- publication, while the new snapshot must retract the Work posting.
  let some id ← findNode? snapshot (owner "alpha" "ALPHA_ONE").relation |
    throw (IO.userError "missing retirement fixture")
  let _ ← DB.PageMap.withWriter snapshot fun writer => do
    removeRoot writer id
    writeChange writer ⟨[],[id],false⟩
  queryCheck (← DB.PageMap.pin one) unions [] "alpha" ["ALPHA_TWO","BETA"]
  queryCheck snapshot unions [] "alpha" ["ALPHA_ONE","ALPHA_TWO","BETA"]
  IO.FS.writeFile (folder / "result.json") (Json.mkObj [
    ("cases",toJson (13 : Nat)),("mixedCongruence",toJson true),
    ("unmentionedLiteral",toJson true),("localRetraction",toJson true),
    ("persistentRetraction",toJson true),("exactFingerprintBarrier",toJson true),
    ("twoPinnedDatabases",toJson true),("liveOwnerRetirement",toJson true),
    ("oldSnapshotStable",toJson true),("adopted",toJson false)]).pretty

private def run (database output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous scale result"
  FileSystem.privateDirectory output
  let snapshot ← DB.PageMap.pin database
  let originals ← oracleRows snapshot
  let some (_,work) := originals.head? | throw (IO.userError "empty oracle")
  let .atom query := work | throw (IO.userError "nontext source Work")
  let stored ← generators snapshot
  let alias := "work-class-unseen-spelling".toUTF8
  let localEdge ← edge (.atom alias) work true
  let localEdges := [localEdge]
  let full ← fullOracle (originals.map Prod.snd) stored localEdges
  let expected := originals.filter fun row => full.quotient.toEquality.same (.atom alias) row.2
  let started ← IO.monoNanosNow
  let classes ← prepared stored localEdges
  let prepareUs := ((← IO.monoNanosNow)-started)/1000
  let mut records := []
  for (label,asked) in [("literal",query),("local-alias",alias),("absent","work-class-absent".toUTF8)] do
    let expected := if label == "absent" then [] else expected.map Prod.fst
    for trial in List.range 20 do
      -- A fresh pinned reader per observation: request-local page/node caches
      -- cannot accidentally turn this into a same-reader lookup benchmark.
      let pinned ← DB.PageMap.pin database
      let reader ← NodeReader.new pinned
      let readStart ← pinned.reads.get
      let bytesStart ← pinned.readBytes.get
      let started ← IO.monoNanosNow
      let found ← reader.classOwners classes asked
      let elapsedUs := ((← IO.monoNanosNow)-started)/1000
      let reads := (← pinned.reads.get)-readStart
      let bytes := (← pinned.readBytes.get)-bytesStart
      check (found.map (·.ordinal) == expected) "scale point query differs from full oracle"
      let bodies := found.map fun item => Persistence.valueToJson item.edge.relation
      records := Json.mkObj [
        ("case",toJson label),("trial",toJson trial),("elapsedUs",toJson elapsedUs),
        ("pageReads",toJson reads),("readBytes",toJson bytes),("owners",toJson found.length),
        ("orderedOriginalRelationsSha256",toJson (Sha256.hex (toJson bodies).compress.toUTF8))] :: records
  check ((← DB.PageMap.pin database).head == snapshot.head) "original source head changed"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("source",toJson snapshot.head),("sourcePath",toJson database.toString),
    ("sourceOwners",toJson originals.length),("generators",toJson (stored.length+localEdges.length)),
    ("prepareUs",toJson prepareUs),("cases",toJson records.reverse),
    ("allQueriesEqualFullScan",toJson true),("freshRequestReaders",toJson true),
    ("sourceHeadUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("endToEndHookMeasured",toJson false),("adopted",toJson false)]).pretty

def main (args : List String) : IO Unit := do
  match args with
  | ["small",output] => small (.mk output)
  | ["run",database,output] => run (.mk database) (.mk output)
  | _ => throw (IO.userError "WorkClassAudit small NEW-OUTPUT | run DB NEW-OUTPUT")
