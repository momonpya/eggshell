module
public import Eggshell.SynapseBuild
@[expose] public section
open Lean Eggshell Eggshell.DB Eggshell.Synapses

namespace Eggshell.Research.FactDeltaChecks

#print axioms Index.Delta.between_added
#print axioms Index.Delta.between_removed
#print axioms Index.Delta.between_exact

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def canonical (facts : Array Fact) : IO (Array Fact) :=
  return (← IO.ofExcept (Synapses.Graph.ofFacts facts)).snapshot

def rows (index : PageMap.Snapshot) : IO (Array (String × Option ByteArray)) :=
  index.foldRange ⟨"", "\x7f"⟩ (fun found row => pure (found.push row)) #[]

def inspect (path destination : System.FilePath) : IO Unit := do
  check (!(← destination.pathExists)) "preserve previous row-difference report"
  let source ← PageMap.pin path
  let some actual ← Index.open? source .database .shared | throw (IO.userError "actual index missing")
  let some reference ← Index.open? source .user .shared | throw (IO.userError "reference index missing")
  let left ← rows actual.index
  let right ← rows reference.index
  let keys := (left.toList.map Prod.fst ++ right.toList.map Prod.fst).eraseDups
  let digest := fun (row : Option (String × Option ByteArray)) =>
    row.bind Prod.snd |>.map (fun bytes => Json.mkObj [("sha256",toJson (Sha256.hex bytes)),
      ("text",toJson (String.fromUTF8? bytes))])
  let different := keys.filterMap fun key =>
    let a := left.find? (·.1 == key)
    let b := right.find? (·.1 == key)
    if a == b then none else some (Json.mkObj [("key",toJson key),("actual",toJson (digest a)),("reference",toJson (digest b))])
  let report := Json.mkObj [("factsEqual",toJson ((← Index.allFacts actual.index) == (← Index.allFacts reference.index))),
    ("actualRows",toJson left.size),("referenceRows",toJson right.size),("differences",toJson different)]
  IO.FS.writeFile destination report.pretty
  IO.println (Json.mkObj [("factsEqual",report.getObjValD "factsEqual"),("differentRows",toJson different.length)]).compress

/-- Exercise real atomic fact/posting/routing publications. The separate user
index is maintained through full replacement with the same immutable source. -/
def run (path : System.FilePath) : IO Json := do
  let source ← PageMap.create path "exact fact delta fixture"
  let fingerprint := String.ofList (List.replicate 64 'a')
  let file : File := ⟨"fixture/records.txt", fingerprint, 65536⟩
  let read := fun (i : Nat) => ({
    occurrence := ⟨"session", "turn", s!"read-{i}"⟩
    source := ⟨file, i+1, i+1⟩
    binding := ⟨source.head.identity, s!"owner-{i}", s!"work-{i}", i*10, i*10+8⟩} : Read)
  let support ← IO.ofExcept (Support.checked (read 0) (read 0).source ⟨source.head.identity,"answer",0,10⟩)
  let consumed : Consumption := {
    producer := (read 0).occurrence, consumer := (read 1).occurrence,
    producerFinish := 1, consumerStart := 2, kind := .identifier, term := "fixture",
    inputFirst := 0, inputLimit := 7, outputFirst := 0, outputLimit := 7, rows := #[(read 0).source]}
  let initial ← canonical ((Array.range 128).map (fun i => .read (read i)) ++
    #[.supports support, .consumed consumed,
      .coquoted (.answer source.head.identity "answer") (read 0).source,
      .coquoted (.answer source.head.identity "answer") (read 1).source])
  let _ ← Index.replace source .database .shared initial
  let _ ← Index.replace source .user .shared initial
  let some pinned ← Index.open? source .database .shared | throw (IO.userError "initial delta fixture not ready")
  let originalRows ← rows pinned.index
  let empty := Index.Delta.between initial initial
  check (empty.added.isEmpty && empty.removed.isEmpty) "unchanged affected facts produced a physical update"
  let started ← IO.monoMsNow
  let unchanged ← Index.publishDelta source .database .shared (some source.head) empty
  let unchangedMs := (← IO.monoMsNow)-started
  check (unchanged == pinned.index.head) "empty delta appended pages or changed the published root"
  let controlStarted ← IO.monoMsNow
  let control ← Index.publishDelta source .database .shared (some source.head) {added := initial}
  let redundantMs := (← IO.monoMsNow)-controlStarted
  check (control == unchanged) "the prior redundant publication changed logical content"
  let next ← canonical ((initial.filter fun fact => fact != .read (read 3) && fact != .consumed consumed) ++
    #[.read (read 129)])
  let delta := Index.Delta.between initial next
  check (delta.removed.size == 2 && delta.added.size == 1) "affected-domain difference included retained facts"
  let _ ← Index.publishDelta source .database .shared (some source.head) delta
  let _ ← Index.replace source .user .shared next
  let some actual ← Index.open? source .database .shared | throw (IO.userError "updated index not ready")
  let some oracle ← Index.open? source .user .shared | throw (IO.userError "full replacement oracle not ready")
  check ((← canonical (← Index.allFacts actual.index)) == next && (← rows actual.index) == (← rows oracle.index))
    "fact delta differs from full fact/posting/binding/routing rows"
  let keys := ((initial ++ next).toList.flatMap fun fact => (Index.addresses fact).toList).eraseDups
  for key in keys do
    let found ← actual.lookup key 100000 ((← IO.monoMsNow)+5000)
    let expected := next.filter (fun fact => (Index.addresses fact).contains key)
    check (found.complete && (← canonical found.facts) == (← canonical expected))
      "an added, retained or retired posting differs from its exact fact projection"
  check ((← rows pinned.index) == originalRows) "new delta changed an older pinned reader"
  let backwards := Index.Delta.between next initial
  let _ ← Index.publishDelta source .database .shared (some source.head) backwards
  let _ ← Index.replace source .user .shared initial
  let restored ← PageMap.pin pinned.index.directory
  let referenceRestored ← PageMap.pin oracle.index.directory
  check ((← canonical (← Index.allFacts restored)) == initial && (← rows restored) == (← rows referenceRestored) &&
    (← rows pinned.index) == originalRows) "reverse delta differs from full replacement or changed an old pin"
  return Json.mkObj [("initialFacts",toJson initial.size),("changedAdded",toJson delta.added.size),
    ("changedRemoved",toJson delta.removed.size),("unchangedAdded",toJson empty.added.size),
    ("unchangedRemoved",toJson empty.removed.size),("unchangedPublishMs",toJson unchangedMs),
    ("redundantPriorPublishMs",toJson redundantMs),("allFactPostingBindingAndRoutingRowsEqual",toJson true),
    ("oldPinUnchanged",toJson true),("reverseUpdateEqualsFullReplacement",toJson true)]

end Eggshell.Research.FactDeltaChecks
