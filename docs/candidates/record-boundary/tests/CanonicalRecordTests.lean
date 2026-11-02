import Eggshell.CanonicalSourceRecords
import tools.research.PreparedSourceView
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

#print axioms Records.Record.payload_bounded
#print axioms Records.complete_payload_retained
#print axioms Records.observed_boundary_retained

private def file : File := ⟨"src/example",String.ofList (List.replicate 64 'a'),100000⟩
private def row (line : Nat) (code : String) (source : File := file) : StoredRow :=
  ⟨⟨source,line⟩,code,#[⟨⟨"fixture","turn","read"⟩,
    ⟨"fixture","owner","work",line*100,line*100+code.length+1⟩⟩]⟩
private def check (test : Bool) (message : String) : IO Unit :=
  unless test do throw (IO.userError message)
private def numbers (rows : Array StoredRow) : Array Nat :=
  ((rows.map (·.key.line)).toList.eraseDups.mergeSort (· ≤ ·)).toArray

def main : IO Unit := do
  let rows := #[row 10 "",row 11 "entry",row 12 "    data",row 13 "  data",
    row 14 "end",row 15 "",row 30 "unrelated",row 31 ""]
  let records := Records.prepare rows
  check (!records.isEmpty) "an observed bounded record was lost"
  check (numbers (Records.close rows records [⟨1,by decide⟩]) == #[11,12,13,14,15])
    "data and its observed boundary were separated"
  check ((Records.close rows records [⟨6,by decide⟩]).map (·.key.line) == #[30])
    "an unbounded paragraph was broadened"
  check (Records.close rows records []).isEmpty "empty demand invented context"

  let changed := {file with fingerprint := String.ofList (List.replicate 64 'b')}
  check (Records.prepare #[row 10 "",row 11 "entry",row 12 "" changed]).isEmpty
    "a paragraph crossed a file fingerprint"
  check (Records.prepare #[row 10 "",row 11 "entry",row 13 ""]).isEmpty
    "a paragraph crossed an unobserved line"
  check (Records.prepare #[row 10 "",row 11 (String.ofList (List.replicate 2048 'x')),row 12 ""]).isEmpty
    "a paragraph escaped the unchanged payload bound"
  check ((Records.prepare #[row 1 "start",row 2 "end",row 3 ""]).length == 1)
    "observed file beginning was lost"

  let continuation := #[row 9 "    prior",row 10 "  entry",row 11 "      data",
    row 12 "    data",row 13 "  next"]
  check (numbers (Records.close continuation (Records.prepare continuation) [⟨1,by decide⟩]) == #[10,11,12,13])
    "a non-punctuation closing boundary was removed"

  let readStart := #[row 40 "  entry",row 41 "    data",row 42 "  end"]
  check (numbers (Records.close readStart (Records.prepare readStart) [⟨0,by decide⟩]) == #[40,41,42])
    "an observed indented record required an unobserved predecessor"
  check (Records.prepare #[row 40 "entry",row 41 "  data"]).isEmpty
    "an unobserved boundary was invented"
  check (Records.prepare #[row 40 "entry",row 42 "  data",row 43 "end"]).isEmpty
    "an indented record crossed an unobserved line"
  check (Records.prepare #[row 40 "entry",row 41 "  data",row 42 "end" changed]).isEmpty
    "an indented record crossed a fingerprint"
  let costly := #[row 40 "entry",row 41 "  data",row 42 (String.ofList (List.replicate 2048 'x'))]
  check (Records.prepare costly).isEmpty "the closing boundary was not charged to the payload bound"
  check ((Records.catalogue costly (Records.prepare costly)).flatten.length == costly.size)
    "rejecting an oversized record discarded original singleton rows"

  let stored ← IO.ofExcept (Recipe.compile readStart)
  let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
  let view ← IO.ofExcept (PreparedSourceView.decodeOwner "fixture" "owner"
    (PreparedSourceView.ownerStored "owner" stored layout))
  check (view.units.any fun unit => unit.keys.map (·.line) == #[40,41,42])
    "published catalogue split the observed boundary from its data"
  let groups ← IO.ofExcept (PreparedSourceView.groupedUnits "owner" view [[(4000,4001)]])
  check (groups.any fun unit => unit.keys.map (·.line) == #[40,41,42])
    "query grouping lost the publication-time boundary"
  IO.println (Json.mkObj [("observedBoundaries",toJson true),("readStart",toJson true),
    ("publishedAndGroupedUnits",toJson true),("gapsAndFingerprintsRejected",toJson true),
    ("boundedWithSingletonCoverage",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("embeddingCalls",toJson (0 : Nat)),("fullHookMeasured",toJson false)]).compress
