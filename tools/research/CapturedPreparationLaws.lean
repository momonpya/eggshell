import Eggshell.DB.PageMap

namespace Eggshell.Research.CapturedPreparationLaws
open Eggshell.DB PageMap

theorem recovery_append_keeps_blob (before appended : ByteArray) (published : Nat)
    (complete : published ≤ before.size) (blob : Blob)
    (committed : blob.offset+blob.bytes ≤ published) :
    ((before.extract 0 published)++appended).extract blob.offset (blob.offset+blob.bytes) =
      before.extract blob.offset (blob.offset+blob.bytes) := by
  have within : blob.offset+blob.bytes ≤ (before.extract 0 published).size := by
    simpa only [ByteArray.size_extract,Nat.min_eq_left complete,Nat.sub_zero] using committed
  rw [blob_bytes_preserved_by_append _ _ _ within]
  exact blob_bytes_preserved_by_recovery before published blob committed

/-- The later blob need not belong to the older logical basis. Both survive
recovery and append at the physical publication, using the real retained-head
and blob types. Native IO must implement these byte operations separately. -/
theorem branch_keeps_both (origin : Snapshot) (basis : Head)
    (reader : HistoryReader origin basis) (older : PinnedBlob basis)
    (later : PinnedBlob origin.head) (before appended : ByteArray)
    (complete : origin.head.bytes ≤ before.size) :
    (((before.extract 0 origin.head.bytes)++appended).extract older.ref.offset
        (older.ref.offset+older.ref.bytes) =
      before.extract older.ref.offset (older.ref.offset+older.ref.bytes)) ∧
    (((before.extract 0 origin.head.bytes)++appended).extract later.ref.offset
        (later.ref.offset+later.ref.bytes) =
      before.extract later.ref.offset (later.ref.offset+later.ref.bytes)) :=
  ⟨recovery_append_keeps_blob before appended _ complete older.ref
      (Nat.le_trans older.committed reader.retained),
    recovery_append_keeps_blob before appended _ complete later.ref later.committed⟩

#check Eggshell.DB.PageMap.withWriterFrom
#print axioms recovery_append_keeps_blob
#print axioms branch_keeps_both

end Eggshell.Research.CapturedPreparationLaws
