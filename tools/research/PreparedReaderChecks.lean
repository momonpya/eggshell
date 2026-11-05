import Main
open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.PreparedReaderChecks
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def refused (action : IO α) : IO Bool := do try let _ ← action; return false catch _ => return true
def traces (sources : Array PageMap.Snapshot) : IO Json := do
  let rows ← sources.mapM fun source => do
    let some trace ← source.trace.get | throw (IO.userError "requester trace disappeared")
    check trace.complete "native prepared-reader trace overflow"
    return (trace.operations.map fun operation =>
      (PageMap.readObservationCodec.encode operation).map UInt8.toNat,trace.encodedBytes,trace.complete)
  return toJson rows
def prepared (sources : Array PageMap.Snapshot) : IO (Array PreparedInputs.Reference × OwnerViews.Reference) := do
  let inputs ← sources.mapM fun source => do
    let some input ← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "native audit original is not prepared")
    return input
  let some owners ← OwnerViews.load? sources | throw (IO.userError "native audit owner frame unavailable")
  return (inputs,owners)
def allPositions (reader : OwnerViews.Reader) : IO Json := do
  let ids ← match reader.base.allOwners with
    | none => pure []
    | some root => reader.base.bitmap.members root.height root
  let positions ← ids.mapM fun id => do
    let binding ← Plugin.preparedOwnerBinding reader id
    return (id,binding.originals)
  return toJson positions
def captured (root : System.FilePath) : IO Unit := do
  let (mixed,latest) ← IO.ofExcept (fromJson? (← read (root/"captured.json")) :
    Except String (Array SourceOwners.Captured × Array SourceOwners.Captured))
  let pages ← PageMap.PagePool.new
  let mut rows := #[]
  for cut in [mixed,latest] do
    let some base ← SourceOwners.open? cut "project/authorized-scope" |
      throw (IO.userError "synthetic captured owner roots were unavailable")
    let sources := base.inputs.map (·.original)
    let mut stride := 1
    for source in sources do stride := max stride ((← getNat source.get "roots")+1)
    let reader : OwnerViews.Reader := ⟨base,stride⟩
    let image ← PreparedReaders.Owners.capture pages reader
      (sources.map fun _ => ⟨[],0,true⟩)
    for source in sources do source.trace.set (some {})
    let expected ← allPositions reader
    let observations ← traces sources
    for source in sources do source.trace.set (some {})
    let borrowed ← image.borrow pages sources
    let actual ← allPositions borrowed
    check (expected == actual && observations == (← traces sources)) "retained owner image changed a synthetic historical/Exact cut"
    let before ← borrowed.base.bitmap.next.get
    let _ ← borrowed.base.bitmap.put 0 {bits := 1}
    let second ← image.borrow pages sources
    check ((← second.base.bitmap.next.get) == before) "synthetic owner image retained transient query mutations"
    check (← refused (image.borrow pages sources.reverse)) "synthetic image silently reordered its originals"
    rows := rows.push (Json.mkObj [("positions",actual),("counts",toJson (← second.counts)),
      ("sources",toJson (sources.map SourceOwners.refOf)),("traces",observations),
      ("allPassed",toJson true)])
  IO.FS.writeFile (root/"prepared-readers.json") ((toJson rows).compress++"\n")
  IO.println (toJson (rows.map fun row => row.getObjValD "counts")).compress
def inspect (sources : Array PageMap.Snapshot) (inputs : Array PreparedInputs.Reference)
    (reference : OwnerViews.Reference) (pool : Option PreparedReaders.Pool) : IO Json := do
  for source in sources do source.trace.set (some {})
  let began ← IO.monoNanosNow
  let image ← pool.mapM fun pool => pool.acquire sources inputs (some reference)
  let shared ← (sources.zip inputs).mapM fun (source,input) =>
    Synapses.Recommend.capturedLocal source input (image.map fun image => image.shared source input)
  let owners ← match image with
    | none => OwnerViews.restore reference sources
    | some image => image.owners sources reference
  let restored ← IO.monoNanosNow
  let ids ← match owners.base.allOwners with
    | none => pure []
    | some root => owners.base.bitmap.members root.height root
  let positions ← ids.mapM fun id => do
    let binding ← Plugin.preparedOwnerBinding owners id
    return (id,binding.originals)
  let observations ← traces sources
  let mut mutableIsolated := true
  if let some image := image then
    let start ← owners.base.bitmap.next.get
    let _ ← owners.base.bitmap.put 0 {bits := 1}
    owners.base.dictionary.trace.set (some {})
    let other ← image.owners sources reference
    mutableIsolated := (← other.base.bitmap.next.get) == start &&
      (← other.base.bitmap.reads.get) == 0 && (← other.base.dictionary.trace.get).isNone &&
      (← other.base.dictionary.reads.get) == 0
    check mutableIsolated "borrowers shared mutable bitmap/counter/trace state"
  return Json.mkObj [("resident",toJson pool.isSome),("restoreNs",toJson (restored-began)),
    ("positions",toJson positions),("counts",toJson (← owners.counts)),
    ("shared",toJson (shared.map fun row => row.shared.map fun reader => (reader.index.head,reader.manifest))),
    ("traces",observations),("mutableBorrowersIsolated",toJson mutableIsolated)]
def run (source root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute reader audit root required"
  IO.FS.createDirAll root
  let config := root/"eggshell.toml"
  let projectPath := (source/"work.project").toString
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = false\n[eggs]\nwork = \""++projectPath++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\n")
  let warm ← IO.Process.output {
    cmd := (← IO.appPath).toString
    args := #["egg","warm",projectPath]
    env := #[("EGGSHELL_CONFIG",some config.toString)]}
  IO.FS.writeFile (root/"warm-stdout.json") warm.stdout
  IO.FS.writeFile (root/"warm-stderr.txt") warm.stderr
  let stopped ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["publication-control","shutdown"]}
  check (warm.exitCode == 0 && stopped.exitCode == 0) "native audit warm or orderly service shutdown failed"
  let project ← ProjectStore.openProject (source/"work.project")
  let expected ← IO.ofExcept (fromJson? ((← read (source/"frozen-readback.json")).getObjValD "sourceHeads") : Except String (Array PageMap.Head))
  let cut : ProjectStore.Cut := ⟨project.manifest.identity,expected⟩
  let initial ← ProjectStore.openView project cut
  let (inputs,reference) ← prepared initial.sources
  let pool ← PreparedReaders.Pool.new
  let mut rows := #[]
  for pair in [:3] do
    for cached in (if pair == 1 then [true,false] else [false,true]) do
      let view ← ProjectStore.openView project cut
      rows := rows.push ((← inspect view.sources inputs reference (if cached then some pool else none)).setObjVal! "pair" (toJson pair))
      IO.FS.writeFile (root/"rows.json") ((toJson rows).compress++"\n")
  let first := rows[0]!
  for row in rows do
    for name in ["positions","counts","shared","traces"] do
      check (row.getObjValD name == first.getObjValD name) ("resident prepared observation differs: "++name)
  let view ← ProjectStore.openView project cut
  let privateInputs := inputs.map fun input => {input with usage := some input.source}
  let changedPrivate ← pool.acquire view.sources privateInputs (some reference)
  let some slot := inputs.findIdx? (fun input => input.population > 0 && input.shared.isSome) |
    throw (IO.userError "no populated prepared shared source")
  let some original := view.sources[slot]? | throw (IO.userError "missing audit source")
  let some originalInput := inputs[slot]? | throw (IO.userError "missing audit input")
  let some privateInput := privateInputs[slot]? | throw (IO.userError "missing private audit input")
  let _ ← changedPrivate.shared original privateInput
  check (← refused (Synapses.Recommend.capturedLocal original privateInput
    (some (changedPrivate.shared original privateInput)))) "resident public image bypassed invalid private usage"
  let badProducer := inputs.modify slot fun input => {input with producer := "foreign-producer"}
  check (← refused (pool.acquire view.sources badProducer (some reference))) "foreign prepared producer accepted"
  check (← refused (pool.acquire view.sources inputs (some {reference with sources := reference.sources.pop})))
    "missing original owner accepted"
  let changedRoot := inputs.modify slot fun input =>
    {input with shared := input.shared.map fun root => {root with head := {root.head with bytes := root.head.bytes+1}}}
  check (← refused (pool.acquire view.sources changedRoot (some reference))) "changed public root reused an old image"
  check (← refused (changedPrivate.owners view.sources {reference with producer := "foreign-owner-producer"}))
    "borrowed owner image accepted a changed descriptor"
  let reordered := {reference with sources := reference.sources.reverse,items := reference.items.reverse}
  let left ← inspect view.sources.reverse inputs.reverse reordered none
  let right ← inspect view.sources.reverse inputs.reverse reordered (some pool)
  for name in ["positions","counts","shared","traces"] do
    check (left.getObjValD name == right.getObjValD name) ("reordered full inventory differs: "++name)
  let other ← ProjectStore.create (root/"other.project") 2
  let otherView ← ProjectStore.pin other ((← IO.monoMsNow)+10000)
  let otherInputs := otherView.sources.map fun source => PreparedInputs.empty source MiniLM.model SearchProvider.encoderContract
  let otherBorrow ← pool.acquire otherView.sources otherInputs none
  check (← refused (otherBorrow.shared original originalInput)) "public cache crossed project scopes"
  let combined ← pool.acquire (view.sources++otherView.sources) (inputs++otherInputs) none
  let _ ← combined.shared original originalInput
  check (← refused (combined.owners view.sources reference)) "mixed project image dropped part of its original boundary"
  let current ← (List.range 16).toArray.mapM project.current
  check (current.map (·.head) == expected) "native reader audit changed the frozen original cut"
  let report := Json.mkObj [("allPassed",toJson true),("rows",toJson rows),
    ("reordered",toJson (left,right)),("pool",← pool.stats),
    ("sourceHeadsUnchanged",toJson true),("privateUsageStillValidated",toJson true),
    ("changedPublicRootRejected",toJson true),("completeMixedProjectBoundary",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.compress++"\n")
  IO.println (Json.mkObj [("allPassed",toJson true),("pool",← pool.stats),
    ("timings",toJson (rows.map fun row => (row.getObjValD "pair",row.getObjValD "resident",row.getObjValD "restoreNs")))]).compress
end Eggshell.Research.PreparedReaderChecks
