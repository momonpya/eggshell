
open Eggshell.Plugin.OriginalRecordPrice
theorem record_price_matches_existing_fragment (original : IndexedCharacters source)
    (span : OriginalStructure.Span) (range : EvidenceRange source)
    (first : range.start = span.first) (last : range.stop = span.limit) (compact : Bool) :
    (prepare original span).cost compact =
      Cost.ofText ((SharedRangeAdapter.originalRecordFragment original range span.decoded).render compact) := by
  rw [prepared_cost_exact]
  simp only [fragment,SharedRangeAdapter.originalRecordFragment,first,last]

def recordPriceChecks (root : System.FilePath) : IO Unit := do
  let check := Eggshell.Research.LexicalGraphHooks.check
  check (root.isAbsolute && !(← root.pathExists)) "fresh record price fixture required"
  IO.FS.createDirAll root
  let sources := #["", "plain\nsource\n", "日本語é한글🙂\n", "{\"text\":\"line\\nquote\\\"\\t日本語\"}",
    "{\"items\":[{\"body\":\"hello world\"},{\"body\":\"other\"}]}\n", "invalid \\uFFFF JSON", String.ofList (List.replicate 20000 '界'),
    (toJson ((List.range 500).map fun n => s!"record-{n}-日本語")).compress]
  let first ← Eggshell.DB.PageMap.create (root/"index") "prepared-original-prices"
  let mut documents := #[]
  for (source,index) in sources.zipIdx do
    let doc : Eggshell.Synapses.Extraction.Document := {
      owner := s!"owner-{index}"
      work := s!"work-{index}"
      workText := some "observed tool output"
      source := some source
      native := true
      occurrences := #[]
      files := #[]}
    documents := documents.push doc
  let (_,head,_) ← Eggshell.DB.PageMap.withWriter first fun writer => do
    for document in documents do
      Eggshell.Synapses.ObservedRecordView.stage writer "database" document
  let pinned := {first with head}
  let mut checked := 0
  let mut rows := #[]
  for document in documents do
    let some view ← Eggshell.Synapses.ObservedRecordView.load? pinned "database" document.owner |
      throw (IO.userError "published original prices missing")
    let source := document.source.getD ""
    let original := IndexedCharacters.make source
    check (view.spans == view.prices.map (·.span)) "price coordinates differ from original recipes"
    check ("".intercalate view.blocks.toList == source) "publication changed the original bytes"
    for stored in view.prices do
      check (stored == prepare original stored.span) "stored metadata differs from fresh exact rendering"
      check stored.bounded "published price is outside the read bound"
      let some range := stored.span.range? source | throw (IO.userError "invalid original range")
      for compact in [false,true] do
        let rendered := (SharedRangeAdapter.originalRecordFragment original range stored.span.decoded).render compact
        let cost := stored.cost compact
        check (cost.characters == rendered.length+1 && cost.bytes == rendered.utf8ByteSize+1)
          "prepared price differs from existing planner rendering"
      checked := checked+2
    rows := rows.push (Json.mkObj [("owner",toJson document.owner),("sourceBytes",toJson source.utf8ByteSize),
      ("records",toJson view.prices.size),("metadataBytes",toJson (toJson view.prices).compress.utf8ByteSize)])
  let result := Json.mkObj [("cases",toJson sources.size),("checkedPresentations",toJson checked),
    ("rows",toJson rows),("allPassed",toJson true),("selectorConnected",toJson false),
    ("adopted",toJson false)]
  IO.FS.writeFile (root/"result.json") result.compress
  IO.println result.compress
