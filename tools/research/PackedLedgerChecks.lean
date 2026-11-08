module
public import tools.research.PackedLedgerProjection
public import Eggshell.SynapseUsage
public import Eggshell.SynapseJournal
@[expose] public section

namespace Eggshell.Research.PackedLedgerChecks
open Lean DB Synapses DeliveryLedger

def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def readJson (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)

def canonical (ranges : Array Range) : Array Range :=
  (Extraction.compactRanges ranges).qsort fun a b => (toJson a).compress < (toJson b).compress

def delivered (projection : Projection) (database : String) : Array Range :=
  projection.rows.filterMap fun row => if row.database == database then some row.source else none

def fileSubject (fingerprint : Char) : Subject := .file {
  relative := "tree/input",fingerprint := String.ofList (List.replicate 64 fingerprint),bytes := 100 }

def controls : IO Json := do
  let subjects := #[fileSubject 'a',fileSubject 'b',.original ⟨"work",String.ofList (List.replicate 64 'c'),100⟩]
  let mut checked := 0
  let mut labels := 0
  for secondDatabase in ["a","b"] do
    for secondSubject in subjects do
      for a in [1:6] do
        for b in [a:7] do
          for c in [1:6] do
            for d in [c:7] do
              let rows : Array Row := #[⟨"a",⟨subjects[0]!,a,b⟩⟩,⟨secondDatabase,⟨secondSubject,c,d⟩⟩]
              let input : Projection := {rows,verified := true,complete := false}
              let packed := PackedLedgerProjection.compact input
              check (packed.confirmable && packed.bindings == input.bindings && packed.verified && !packed.complete)
                "compaction changed verification or binding authority"
              for database in ["a","b","foreign"] do
                let old := delivered input database
                let proposed := delivered packed database
                check (canonical old == canonical proposed) "canonical delivered ranges differ"
                for subject in subjects do
                  for first in [1:8] do
                    for last in [first:8] do
                      let wanted : Range := ⟨subject,first,last⟩
                      check (covered wanted old == covered wanted proposed) "legacy coverage changed on a gap/boundary/scope"
                      for fingerprintChecked in [false,true] do
                        let stored := #[⟨subject,1,8⟩]
                        check (readKind wanted stored old fingerprintChecked ==
                          readKind wanted stored proposed fingerprintChecked) "implicit reuse label changed"
                        labels := labels+1
              checked := checked+1
  let invalid : Array Projection := #[
    {rows := #[⟨"a",⟨subjects[0]!,9,2⟩⟩],verified := true},
    {rows := #[⟨"",⟨subjects[0]!,1,2⟩⟩],verified := true},
    {rows := #[⟨"a",⟨subjects[0]!,0,2⟩⟩],verified := true},
    {rows := #[⟨"a",⟨subjects[0]!,1,2⟩⟩],verified := false,complete := true}]
  for input in invalid do
    check (!input.confirmable && PackedLedgerProjection.compact input == input)
      "invalid metadata was normalized into an accepted projection"
  return Json.mkObj [("projections",toJson checked),("readKindComparisons",toJson labels),
    ("invalidPreserved",toJson invalid.size),("separateFingerprintAndOriginalScopes",toJson true)]

def originalProjection (path : System.FilePath) : IO (PageMap.Snapshot × Projection) := do
  let source ← PageMap.pin path
  let rows ← source.foldRange ⟨"range:","range;"⟩ (fun rows (name,bytes) => do
    let some bytes := bytes | throw (IO.userError "missing range")
    let some text := String.fromUTF8? bytes | throw (IO.userError "invalid range text")
    let value : Row ← IO.ofExcept (Json.parse text >>= fromJson?)
    check (value.valid && name == rowKey value && (toJson value).compress == text) "unvalidated original range"
    return rows.push value) (#[] : Array Row)
  let bindings ← source.foldRange ⟨"binding:","binding;"⟩ (fun rows (name,bytes) => do
    let some bytes := bytes | throw (IO.userError "missing binding")
    let some text := String.fromUTF8? bytes | throw (IO.userError "invalid binding text")
    let value : Binding ← IO.ofExcept (Json.parse text >>= fromJson?)
    check (value.valid && name == bindingKey value && (toJson value).compress == text) "unvalidated original binding"
    return rows.push value) (#[] : Array Binding)
  return (source,{rows,bindings,verified := true,complete := false})

def run (manifest originalDatabase output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous packed ledger result"
  let control ← controls
  let input ← readJson manifest
  let directory : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "directory"))
  let (source,projection) ← originalProjection directory
  let expected : Reference ← IO.ofExcept (input.getObjVal? "reference" >>= fromJson?)
  check (source.head == expected.head && input.getObjValD "knowledgeUncertain" == toJson true &&
    projection.rows.size == 5697 && projection.bindings.size == 62) "the exact accepted uncertain ACK input changed"
  let original ← PageMap.pin originalDatabase
  let fixture ← IO.mkRef projection
  let mut results := #[]
  for repetition in [:3] do
    let order := if repetition%2 == 0 then #[false,true] else #[true,false]
    let mut arms := #[]
    let mut presentations := #[]
    for packed in order do
      let began ← IO.monoMsNow
      let value ← fixture.get
      let value := if packed then PackedLedgerProjection.compact value else value
      let reference ← confirm s!"packed-ledger-{repetition}-{packed}" 1 none value
      let elapsed := (← IO.monoMsNow)-began
      let some reference := reference | throw (IO.userError "native confirmation omitted its head")
      let ranges ← lookup reference original.head.identity
      let absent ← lookup reference "foreign-project"
      check absent.isEmpty "packed ledger leaked another project"
      let known : Journal.Knowledge := {
        source := original.head,indexed := none,acknowledged := [],uncertain := true,delivery := some reference }
      let shown ← Journal.presentation original known
      presentations := presentations.push (canonical shown.ranges)
      let target ← DeliveryLedger.directory reference.context
      let data ← PageMap.pin target
      let repeatedStarted ← IO.monoMsNow
      let value ← fixture.get
      let value := if packed then PackedLedgerProjection.compact value else value
      let again ← confirm reference.session reference.epoch (some reference) value
      let repeatedMs := (← IO.monoMsNow)-repeatedStarted
      check (again.any fun accepted => accepted.head == reference.head) "unchanged confirmation changed its head"
      arms := arms.push (Json.mkObj [("packed",toJson packed),("confirmMs",toJson elapsed),
        ("repeatMs",toJson repeatedMs),("storedBytes",toJson data.head.bytes),
        ("storedRows",toJson (data.head.root.map (·.rows) |>.getD 0)),
        ("positiveRanges",toJson ranges.size),("bindings",toJson value.bindings.size),
        ("verified",toJson value.verified),("complete",toJson value.complete),
        ("reference",toJson reference)])
    check (presentations[0]! == presentations[1]!) "the actual Journal.presentation changed confirmed coverage"
    results := results.push (Json.mkObj [("repetition",toJson repetition),
      ("sameCanonicalJournalPresentation",toJson true),("arms",toJson arms)])
  check ((← PageMap.pin directory).head == source.head && (← PageMap.pin originalDatabase).head == original.head)
    "confirmation comparison changed the original inputs"
  IO.FS.writeFile output (Json.mkObj [("controls",control),("originalHead",toJson source.head),
    ("sourcePath",toJson directory.toString),("ranges",toJson projection.rows.size),
    ("results",toJson results),("actualNativeConfirmAndJournal",toJson true),
    ("nativeHookConnected",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty

end Eggshell.Research.PackedLedgerChecks

#print axioms Eggshell.Research.ScopedIntervals.pack_covers
#print axioms Eggshell.Research.PackedLedgerProjection.packRows_covers
#print axioms Eggshell.Research.PackedLedgerProjection.packed_valid
#print axioms Eggshell.Research.PackedLedgerProjection.compact_confirmable

def main (args : List String) : IO Unit := do
  let [manifest,original,output] := args | throw (IO.userError "packed-ledger MANIFEST ORIGINAL OUTPUT")
  Eggshell.Research.PackedLedgerChecks.run (.mk manifest) (.mk original) (.mk output)
