import Eggshell.SynapseBuild
import tools.research.CitationRows
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction
namespace SynapseSignalAudit
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def bump (counts : Std.HashMap String Nat) (name : String) : Std.HashMap String Nat :=
  counts.insert name (counts[name]?.getD 0+1)
def scopedAnswer (database : String) (document : Document) (reads : Array LocatedRead) : Except String Eggshell.Synapses.Graph := do
  let some raw := document.source | throw "no original answer"
  let decoded := layoutView raw
  let files := reads.foldl (fun files observation =>
    (observation.read.source.file?.map files.insert).getD files) ({} : Std.HashSet File)
  let originals := reads.flatMap (·.originalRows)
  let mut graph : Eggshell.Synapses.Graph := .empty
  let mut position := 0
  for paragraph in decoded.text.splitOn "\n\n" do
    let stop := position+paragraph.length
    if position < stop then
      let claim : Claim := ⟨database,document.owner,decoded.offsets[position]!,decoded.offsets[stop]!⟩
      for citation in paragraphCitations paragraph files.toArray do
        for located in reads do
          graph ← supportCitations graph claim #[citation] #[located.read]
            (originals.filter (fun row => CitationRows.within located.read row))
    position := stop+2
  return graph
def summary (value : Except String Eggshell.Synapses.Graph) : Json := match value with
  | .error error => Json.mkObj [("error",toJson error)]
  | .ok graph => Json.mkObj [("error",Json.null),
    ("citationSupports",toJson (graph.snapshot.filter fun fact => match fact with | .supports value => value.basis == .citation | _ => false).size),
    ("coquotationFacts",toJson (graph.snapshot.filter fun fact => match fact with | .coquoted .. => true | _ => false).size)]
def run (database output : String) : IO Unit := do
  check (!(← (System.FilePath.mk output).pathExists)) "preserve the earlier signal audit"
  let source ← DB.PageMap.pin database
  let some reader ← Index.openShared? source | throw (IO.userError "no checked shared synaptic publication")
  let facts ← Index.allFacts reader.index
  check (facts.size == reader.manifest.facts) "shared fact count differs from its publication"
  let mut counts : Std.HashMap String Nat := {}
  let mut files : Std.HashSet File := {}
  let mut fileReads : Array Read := #[]
  for fact in facts do
    match fact with
    | .read observation =>
      match observation.source.subject with
      | .file file =>
        counts := bump counts "fileReads"
        files := files.insert file
        fileReads := fileReads.push observation
      | .original _ => counts := bump counts "originalReads"
    | .supports support =>
      counts := bump counts (if support.basis == .citation then "citationSupports" else "spellingSupports")
    | .consumed _ => counts := bump counts "consumptionFacts"
    | .coquoted (.answer ..) _ => counts := bump counts "answerCoquotationFacts"
    | .coquoted (.claim ..) _ => counts := bump counts "claimCoquotationFacts"
    | .used _ => counts := bump counts "usageFacts"
  let nodes ← Persistence.Store.NodeReader.new source
  let topology ← Build.topology source
  let view ← Maintenance.View.new source
  let catalogs : Build.Documents source := {
    reader := nodes,cache := ← IO.mkRef {},catalogs := ← IO.mkRef {},
    prepared := some reader.index,additions := {}}
  let allReads := facts.filterMap fun fact => match fact with | .read value => some value | _ => none
  let mut documents := #[]
  for entry in ← Build.entries source do
    let document ← Build.document nodes entry.id
    if document.native then
      documents := documents.push (Json.mkObj [("owner",toJson document.owner),
        ("native",toJson true),("dependencyFiles",toJson document.files.size)])
    else
      let text := (layoutView (document.source.getD "")).text
      let citations := paragraphCitations text files.toArray
      let supported := citations.filter fun citation => fileReads.any (fun observation =>
        (citation.intersection? observation.source).isSome)
      let route := Build.closure topology #[entry.work]
      let incrementalRoute ← view.closure false #[entry.work]
      check (route == incrementalRoute) "incremental and full Work routes differ"
      let mut available : Std.HashSet Read := {}
      let mut lookupRows := #[]
      for work in route do
        let workKey ← view.workKey work
        let indexed ← Maintenance.readsAt reader workKey
        let complete := allReads.filter (·.binding.work == workKey)
        check ((indexed.foldl (fun (set : Std.HashSet Read) value => set.insert value) {}) ==
          (complete.foldl (fun (set : Std.HashSet Read) value => set.insert value) {}))
          "published Work posting differs from complete fact population"
        for observation in indexed do available := available.insert observation
        lookupRows := lookupRows.push (Json.mkObj [("workKey",toJson workKey),("reads",toJson indexed.size),
          ("fileReads",toJson (indexed.filter (·.source.file?.isSome)).size)])
      let routedReads := available.toArray
      let routeFiles := routedReads.foldl (fun files observation =>
        (observation.source.file?.map files.insert).getD files) ({} : Std.HashSet File)
      let routeCitations := paragraphCitations text routeFiles.toArray
      let needed := routedReads.filter fun observation => routeCitations.any (fun citation =>
        (citation.intersection? observation.source).isSome)
      let mut located := #[]
      let mut owners : Std.HashSet String := {}
      for observation in needed do
        if owners.contains observation.binding.owner then continue
        owners := owners.insert observation.binding.owner
        let some id ← Build.ownerId? source observation.binding.owner | throw (IO.userError "route owner is not live")
        located := located ++ (← catalogs.catalog id).located
      let replay := addAnswer source.head.identity document located .empty
      let boundedReplay := scopedAnswer source.head.identity document located
      documents := documents.push (Json.mkObj [("owner",toJson document.owner),("native",toJson false),
        ("citationsAgainstPublishedFiles",toJson citations.size),
        ("citationsWithPublishedReadOverlap",toJson supported.size),
        ("dependencyFiles",toJson document.files.size),
        ("workRouteSize",toJson route.size),("routeLookups",toJson lookupRows),
        ("availableReads",toJson routedReads.size),("availableFileReads",toJson (routedReads.filter (·.source.file?.isSome)).size),
        ("routeCitations",toJson routeCitations.size),("neededReadOwners",toJson owners.size),
        ("replayedCitationConstruction",summary replay),("replayedWithinOriginalRead",summary boundedReplay)])
  check ((← DB.PageMap.pin database).head == source.head &&
    (← DB.PageMap.pin reader.index.directory).head == reader.index.head) "read-only signal audit changed a publication"
  let names := #["fileReads","originalReads","citationSupports","spellingSupports",
    "consumptionFacts","answerCoquotationFacts","claimCoquotationFacts","usageFacts"]
  let report := Json.mkObj [("source",toJson source.head),("synapticHead",toJson reader.index.head),
    ("facts",toJson facts.size),("counts",Json.mkObj (names.map fun name => (name,toJson (counts[name]?.getD 0))).toList),
    ("distinctPublishedFiles",toJson files.size),("documents",toJson documents),
    ("sourceAndIndexUnchanged",toJson true),("warmOrModelCalled",toJson false)]
  IO.FS.writeFile output report.compress
end SynapseSignalAudit
def main : List String → IO Unit
  | [database,output] => SynapseSignalAudit.run database output
  | _ => throw (IO.userError "SynapseSignalAudit DB OUTPUT")
