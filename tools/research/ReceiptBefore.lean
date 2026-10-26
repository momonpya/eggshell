import Eggshell.SynapseUsage
open Lean Eggshell.Synapses Eggshell.Synapses.Extraction
namespace Eggshell.Research.ReceiptBefore
def sharedPresented (body : String) (docs : Array Document) (reads : Array Read) :
    Array (SharedWitness reads) := Id.run do
  let displayed := sharedSpellings body
  if displayed.isEmpty || reads.isEmpty then return #[]
  let mut index : Std.HashMap (File × Nat × String) (Array (SharedWitness reads)) := {}
  let byOwner := reads.attach.foldl (fun found saved =>
    found.insert saved.val.binding.owner
      ((found.getD saved.val.binding.owner #[]).push saved))
    ({} : Std.HashMap String (Array {row // row ∈ reads}))
  for doc in docs do
    if !doc.native then continue
    let some raw := doc.source | continue
    let characters := raw.toList.toArray
    for saved in byOwner.getD doc.owner #[] do
      let row := saved.val
      if !row.valid || row.binding.work != doc.work || !doc.occurrences.contains row.occurrence then continue
      let .file file := row.source.subject | continue
      if row.source.first != row.source.last then continue
      if !(row.binding.first < row.binding.limit && row.binding.limit ≤ characters.size) then continue
      let original := String.ofList (characters.extract row.binding.first row.binding.limit).toList
      for code in sharedCodes original do
        if code.text.isEmpty || code.text.contains '\n' || code.text.contains '\r' then continue
        if same : row.source = ⟨file,row.source.first,row.source.first⟩ then
          let witness : SharedWitness reads := ⟨row,saved.property,file,row.source.first,code.text,same⟩
          let key := (file,row.source.first,code.text)
          index := index.insert key ((index.getD key #[]).push witness)
    let .ok decoded := layout raw | continue
    for line in textLines decoded.text do
      let some (number,code) := numbered line.text | continue
      for saved in byOwner.getD doc.owner #[] do
        let row := saved.val
        if !row.valid || row.binding.work != doc.work ||
            row.binding.first != decoded.offsets[line.first]! ||
            row.binding.limit != decoded.offsets[line.limit]! then continue
        let .file file := row.source.subject | continue
        if same : row.source = ⟨file,number,number⟩ then
          let witness : SharedWitness reads := ⟨row,saved.property,file,number,code,same⟩
          let key := (file,number,code)
          index := index.insert key ((index.getD key #[]).push witness)
  let mut found := #[]
  for spelling in displayed do
    for witness in index.getD (spelling.file,spelling.number,spelling.code) #[] do
      let row := witness.row
      if spelling.origins.contains (row.binding.database,row.binding.owner,row.binding.work,row.occurrence) then
        found := found.push witness
  return found

end Eggshell.Research.ReceiptBefore
