import Eggshell.ObservedRecordView
open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.Extraction

#print axioms ObservedRecordView.checked_piece_exact
#print axioms ObservedRecords.base_covers

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "keep prior audit")
  IO.FS.createDirAll root
  let texts := #["plain MCP output\nnot a file\n",(toJson "한국어\n日本語\npath:anything\n").compress,
    (Json.mkObj [("customer",toJson "arbitrary"),("result",toJson "line 1\nline 2\n")]).compress,
    String.ofList (List.replicate 6200 'x'),"{}"]
  let mut records := #[]
  let source ← DB.PageMap.create (root / "records.egg") "original-record-audit"
  let mut pinned := source
  for raw in texts do
    let doc : Document := ⟨"owner","work",some "mcp/arbitrary",some raw,true,#[⟨"s","t","use"⟩],#[]⟩
    let view ← IO.ofExcept (ObservedRecordView.make source.head.identity doc)
    unless "".intercalate view.blocks.toList == raw do throw (IO.userError "base block partition lost raw bytes")
    let mut checked := 0
    for start in [:raw.length] do
      let stop := min raw.length (start+137)
      let expected := String.ofList (raw.toList.drop start |>.take (stop-start))
      unless view.slice start stop == some expected do throw (IO.userError "point slice changed literal bytes")
      let pieces := view.pieces start stop
      unless pieces.all (fun piece => (ObservedRecordView.Piece.check? view piece).isSome) do
        throw (IO.userError "unbound original record")
      for position in [start:stop] do
        unless pieces.any (fun piece => piece.span.first ≤ position && position < piece.span.limit) do
          throw (IO.userError "record layout omitted an original character")
      checked := checked+1
    let (_,head,_) ← DB.PageMap.withWriter pinned fun writer =>
      ObservedRecordView.stage writer source.head.identity doc
    pinned ← DB.PageMap.pin (root / "records.egg")
    unless pinned.head == head do throw (IO.userError "prepared record publication lost its root")
    let stored ← ObservedRecordView.load? pinned source.head.identity "owner"
    unless stored.map toJson == some (toJson view) do throw (IO.userError "prepared view changed across storage")
    let reads ← pinned.reads.get
    for _ in [:8] do
      let hot ← ObservedRecordView.load? pinned source.head.identity "owner"
      unless hot.map toJson == some (toJson view) do throw (IO.userError "hot point read changed source")
    unless (← pinned.reads.get) == reads do throw (IO.userError "shared reader repeated physical page reads")
    let rejected ← try
      let _ ← ObservedRecordView.load? pinned "other-database" "owner"
      pure false
    catch _ => pure true
    unless rejected do throw (IO.userError "original view crossed DB scope")
    records := records.push (Json.mkObj [("characters",toJson raw.length),("checkedRanges",toJson checked),
      ("blocks",toJson view.blocks.size),("structuralRecords",toJson view.spans.size)])
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("cases",toJson records),
    ("modelCalls",toJson (0 : Nat)),("actualHook",toJson false),("adopted",toJson false)]).pretty
  IO.println "original block partition, arbitrary point slices and all requested character coverage passed"
