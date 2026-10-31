import tools.research.RecordedNavigation
import tools.research.FrozenCanonicalBasis
import tools.research.ArtifactHash
import tools.research.NativeTrialAudit
open Lean Eggshell Eggshell.Synapses Eggshell.Research.RecordedNavigation
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def fixtures : IO Unit := do
  let subject : Subject := .file ⟨"resource",String.ofList (List.replicate 64 'a'),1000⟩
  let span := fun first last => ({subject,first,last} : Range)
  let header := fun name started finished =>
    ({database := "database",domain := "domain",occurrence := ⟨"session","turn",name⟩,started,finished} : Header)
  let producer : Call := ⟨header "search" 1 2,#[span 10 10,span 30 30]⟩
  let consumer : Call := ⟨header "read" 3 4,#[span 20 20]⟩
  let prepared := prepare #[producer,consumer]
  let expanded := enrich prepared #[span 20 20]
  check (prepared.gapCount == 1 && expanded.additions == #[span 10 10]) "bounded navigation not restored"
  let other := {consumer with header := {consumer.header with database := "other"}}
  check ((enrich (prepare #[producer,other]) #[span 20 20]).additions.isEmpty) "navigation crossed project"
  let overlap := {producer with header := {producer.header with finished := 4}}
  check ((enrich (prepare #[overlap,consumer]) #[span 20 20]).additions.isEmpty) "future or concurrent completion was used"
  let noUpper : Call := ⟨producer.header,#[span 10 10]⟩
  check ((enrich (prepare #[noUpper,consumer]) #[span 20 20]).additions.isEmpty) "unbounded final landmark was expanded"
  let direct : Call := ⟨producer.header,#[span 10 10,span 20 20,span 30 30]⟩
  check ((enrich (prepare #[direct,consumer]) #[span 20 20]).additions.isEmpty) "observed target was treated as a gap"
  let alternate : Call := ⟨header "other-search" 1 2,#[span 15 15,span 35 35]⟩
  check ((enrich (prepare #[producer,alternate,consumer]) #[span 20 20]).additions.isEmpty) "ambiguous tied anchors were chosen"
  let .file file := subject | throw (IO.userError "file fixture changed")
  let changed := {(span 20 20) with subject := .file {file with fingerprint := String.ofList (List.replicate 64 'b')}}
  let changedCall : Call := ⟨consumer.header,#[changed]⟩
  check ((enrich (prepare #[producer,changedCall]) #[changed]).additions.isEmpty) "changed content reused old coordinates"
  let generic : Subject := .original ⟨"resource-operation",String.ofList (List.replicate 64 'c'),100⟩
  let genericSpan := fun position => ({subject := generic,first := position,last := position} : Range)
  let a : Call := ⟨producer.header,#[genericSpan 10,genericSpan 30]⟩
  let b : Call := ⟨consumer.header,#[genericSpan 20]⟩
  check ((enrich (prepare #[a,b]) #[genericSpan 20]).additions == #[genericSpan 10]) "original-output coordinates were excluded"
  let repeated := enrich prepared expanded.ranges
  check repeated.additions.isEmpty "navigation closure is not idempotent"

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh navigation audit directory required")
  let output : System.FilePath := .mk destination
  check (!(← output.pathExists)) "preserve prior navigation audit"
  fixtures
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let sourcePath := study / "r0/stage1/history/source.egg"
  let before ← Eggshell.Research.ArtifactHash.hex (sourcePath / "head")
  let (source,rows) ← Eggshell.Research.FrozenCanonicalBasis.load study root
  let pagesBefore ← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)
  let reader ← Persistence.Store.NodeReader.new source
  let docs ← (← Build.entries source).mapM fun entry => Build.document reader entry.id
  let aliases : Array Read := rows.flatMap fun row => row.origins.map fun origin =>
    ⟨origin.occurrence,⟨row.key.file,row.key.line,row.key.line⟩,origin.binding,#[]⟩
  let originals := docs.flatMap fun doc => (Extraction.recordedRows source.head.identity doc).toOption.getD #[]
  let locations := KeyPostings.prepare (·.occurrence) (aliases ++ originals)
  let chronology ← Provenance.records source
  let mut calls := #[]
  for recorded in chronology do
    let origin := recorded.origin
    let doc ← Provenance.checkedDocument reader origin
    let expected := locations.lookup origin.occurrence |>.filter fun read =>
      read.binding.database == source.head.identity && read.binding.owner == doc.owner && read.binding.work == doc.work
    let ranges := (hashDistinct (expected.toList.map (·.source))).toArray
    calls := calls.push ⟨⟨source.head.identity,origin.domain,origin.occurrence,origin.started,origin.finished⟩,ranges⟩
  let started ← IO.monoMsNow
  let prepared ← IO.mkRef (prepare calls)
  let prepared ← prepared.get
  let prepareMs := (← IO.monoMsNow)-started
  IO.FS.createDirAll output
  let mut staged := #[]
  let mut pending := #[]
  for topic in [1,2,3] do
    let bodyPath := project / s!"docs/candidates/source-plan/bodies/topic-{topic}.txt"
    let body ← IO.FS.readFile bodyPath
    let shown := Extraction.presented body docs (aliases ++ originals)
    let initial := Extraction.compactRanges shown.ranges
    let started ← IO.monoMsNow
    let enriched ← IO.mkRef (enrich prepared initial)
    let enriched ← enriched.get
    let elapsedMs := (← IO.monoMsNow)-started
    let additions := enriched.additions.filter fun range => !covered range initial
    let extraRows := rows.filter fun row => additions.any (fun range =>
      range.contains ⟨row.key.file,row.key.line,row.key.line⟩)
    let diagnostic ← if extraRows.isEmpty then pure body else do
      let some part := CanonicalSource.Delivery.Part.check? extraRows |
        throw (IO.userError "navigation selected invalid original rows")
      pure (body ++ "\n" ++ part.render)
    let shownDiagnostic := Extraction.presented diagnostic docs (aliases ++ originals)
    check (extraRows.all (fun row => covered ⟨row.key.file,row.key.line,row.key.line⟩ shownDiagnostic.ranges))
      "diagnostic renderer hid a selected original row"
    let path := output / s!"topic-{topic}-diagnostic.txt"
    IO.FS.writeFile path diagnostic
    let report := Json.mkObj [("topic",toJson topic),("initialRanges",toJson initial.size),
      ("additions",toJson additions),("addedFileRows",toJson extraRows.size),("firedLinks",toJson enriched.fired.size),
      ("unrenderedOriginalAdditions",toJson (additions.countP (·.subject.file?.isNone))),
      ("closureMs",toJson elapsedMs),("originalBodyChars",toJson body.length),
      ("diagnosticBodyChars",toJson diagnostic.length),("withinOriginalCharacterCap",toJson (decide (diagnostic.length ≤ 120000))),
      ("bodySha256",toJson (Sha256.hex body.toUTF8)),("diagnosticSha256",toJson (Sha256.hex diagnostic.toUTF8))]
    staged := staged.push report
    pending := pending.push (topic,path,Sha256.hex diagnostic.toUTF8)
  -- Every topic's range set and body are sealed before opening human labels.
  IO.FS.writeFile (output / "before-gold.json") (Json.mkObj [
    ("source",toJson source.head),("calls",toJson calls.size),("gaps",toJson prepared.gapCount),
    ("targets",toJson prepared.targets.size),("linkedTargets",toJson (prepared.links.countP Option.isSome)),
    ("prepareMs",toJson prepareMs),("topics",toJson staged)]).pretty
  let frozen ← IO.ofExcept ((← read (project / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let mut audits := #[]
  for (topic,path,sha) in pending do
    let some item := frozen[topic-1]? | throw (IO.userError "missing frozen topic")
    let audit ← Eggshell.Research.NativeTrialAudit.replayAvailable (item.getObjValD "specification") path.toString sha
    check (audit.getObjValD "availableEvidence" == item.getObjValD "available") "navigation changed frozen denominator"
    audits := audits.push (Json.mkObj [("topic",toJson topic),("diagnosticCoverage",audit.getObjValD "availableDelivery")])
  check ((← Eggshell.Research.ArtifactHash.hex (sourcePath / "head")) == before &&
    (← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)) == pagesBefore)
    "read-only navigation audit changed source"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("topics",toJson audits),("selection",toJson staged),("sourceUnchanged",toJson true),
    ("actualHooks",toJson (0 : Nat)),("newSeeds",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("unboundedDiagnostic",toJson true),("adopted",toJson false)]).pretty
  IO.println (toJson audits).compress
