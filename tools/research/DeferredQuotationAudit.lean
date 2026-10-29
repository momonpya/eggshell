import Eggshell.ObservedRecords
open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.Extraction

#print axioms QuotationContext.Source.slice_exact
#print axioms QuotationContext.Located.literal_is_original
#print axioms QuotationContext.Located.context_contains_match
#print axioms ObservationContext.quotation_witness_preserves_origin
#print axioms ObservationContext.Quotation.prepared_mapping_exact

private def doc (raw : String) (owner : String := "owner") (useId : String := "use") : Document :=
  ⟨owner,"work",some "arbitrary MCP/tool",some raw,true,#[⟨"session","turn",useId⟩],#[]⟩

private def catalog (raw : String) (owner : String := "owner") (useId : String := "use") : IO ObservationContext.Catalog := do
  let prepared ← IO.ofExcept (ObservedRecords.prepare raw)
  IO.ofExcept (ObservedRecords.catalog "database" (doc raw owner useId) prepared.records)

private def widths (items : Array ObservationContext.Quotation) : Array Nat :=
  items.map fun item => item.read.binding.limit-item.read.binding.first

private def scenario (raw pattern : String) : IO Json := do
  let catalog ← catalog raw
  let index := LiteralSearch.prepare #[pattern]
  let started ← IO.monoMsNow
  let result := ObservationContext.quoteMatches index catalog.quotations
  let elapsed := (← IO.monoMsNow)-started
  let eager := catalog.quotations.map fun item => {item with mapping := Thunk.pure item.mapping.get}
  let reference := ObservationContext.quoteMatches index eager
  let signature := fun items : Array ObservationContext.Quotation => items.map fun item => (item.read,item.text,item.anchor)
  unless signature result == signature reference do throw (IO.userError "deferred quote projection differs from eager mapping")
  unless !result.isEmpty && result.all (fun item => item.anchor.isSome && item.read.valid &&
      item.read.occurrence == ⟨"session","turn","use"⟩ && item.read.binding.owner == "owner") do
    throw (IO.userError "lost the checked quote or its source observation")
  let legacy := catalog.quotations.filter fun item => !(LiteralSearch.first index item.text).isEmpty
  return Json.mkObj [("rawChars",toJson raw.length),("pattern",toJson pattern),
    ("legacyMatches",toJson legacy.size),("legacyMaxContext",toJson ((widths legacy).foldl max 0)),
    ("matches",toJson result.size),("maxContext",toJson ((widths result).foldl max 0)),
    ("elapsedMs",toJson elapsed),("eagerMappingResultEqual",toJson true)]

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "keep prior quotation audit")
  IO.FS.createDirAll root
  let long := (toJson ("prefix\n" ++ "".intercalate (List.replicate 1200 "日本語 needle suffix\n") ++ "tail\n")).compress
  let large ← scenario long "needle"
  unless (large.getObjValAs? Nat "legacyMaxContext").toOption.getD 0 > 20000 &&
      (large.getObjValAs? Nat "maxContext").toOption.getD 0 < 100 &&
      (large.getObjValAs? Nat "matches").toOption == some 1200 do
    throw (IO.userError "a short quote still supports a whole output or lost repeated rows")
  let nested := (Json.mkObj [("metadata",Json.mkObj [("owner",toJson "needle")]),
    ("message",toJson "first row\nneedle second row\nlast row\n")]).compress
  let metadata ← scenario nested "needle"
  let multiline ← scenario ((toJson "unrelated prefix\nfirst row\nsecond row\nunrelated tail\n").compress) "first row\nsecond row"
  let escaped ← scenario ((toJson "韓国語🙂\nURI mcp://host/a\\b\"needle\"\n尾\n").compress) "b\"needle\""
  let plain ← scenario "header\nneedle plain output\ntrailer\n" "needle"
  let left ← catalog (toJson "needle\n").compress "owner-a" "use-a"
  let right ← catalog (toJson "needle\n").compress "owner-b" "use-b"
  let distinct := ObservationContext.quoteMatches (LiteralSearch.prepare #["needle"]) (left.quotations ++ right.quotations)
  unless distinct.size == 2 && (distinct.map (·.read.occurrence.useId)).toList.eraseDups.length == 2 do
    throw (IO.userError "payload sharing erased another observation's witness")
  let some original := left.located[0]? | throw (IO.userError "missing source fixture")
  let unsupportedRead := original.read
  let unsupported : ObservationContext.Quotation := ⟨unsupportedRead,"needle",Thunk.pure none,none⟩
  let retained := ObservationContext.quoteMatches (LiteralSearch.prepare #["needle"]) #[unsupported]
  unless retained.size == 1 && retained[0]?.any (fun item => item.read == unsupportedRead && item.anchor.isNone) do
    throw (IO.userError "an unsupported projection silently lost its old source record")
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("cases",toJson #[large,metadata,multiline,escaped,plain]),
    ("distinctOriginsRetained",toJson true),("unsupportedProjectionExplicit",toJson true),
    ("modelCalls",toJson (0 : Nat)),("actualHook",toJson false),("adopted",toJson false)]).pretty
