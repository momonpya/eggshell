import Main
open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.ProjectPageReuseChecks
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
def counters (sources : Array PageMap.Snapshot) : IO Json := do
  let values ← sources.mapM fun source => do
    return Json.mkObj [("head",toJson source.head),("reads",toJson (← source.reads.get)),
      ("bytes",toJson (← source.readBytes.get)),("shared",toJson source.sharedPages.isSome),
      ("privatePages",toJson ((← source.cache.get).recent.size+(← source.cache.get).previous.size))]
  return toJson values
def totals (sources : Array PageMap.Snapshot) : IO (Nat × Nat) := do
  let mut counts := (0,0)
  for source in sources do counts := (counts.1+(← source.reads.get),counts.2+(← source.readBytes.get))
  return counts
def trial (project : ProjectStore.Project) (cut : ProjectStore.Cut)
    (pool : Option PageMap.PagePool) (pair : Nat) : IO Json := do
  let scope := ProjectViews.scope project
  let started ← IO.monoNanosNow
  let view ← ProjectStore.openView project cut (pool.map (fun pages => ⟨pages,scope⟩))
  let opened ← IO.monoNanosNow
  check (view.cut == cut && view.sources.map (·.head) == cut.heads) "page audit changed the frozen boundary"
  let opening ← totals view.sources
  let before ← counters view.sources
  let mut graphs := #[]
  let mut traces := #[]
  for source in view.sources do
    source.trace.set (some {})
    let graph ← materialize source
    graphs := graphs.push (Json.mkObj [("authority",Persistence.valueToJson graph.authority),
      ("revision",toJson graph.revision),("values",toJson (graph.values.map Persistence.valueToJson)),
      ("unions",toJson (graph.unions.map fun edge =>
        (Persistence.valueToJson edge.edge.left,Persistence.valueToJson edge.edge.right)))])
    let some trace ← source.trace.get | throw (IO.userError "page audit lost requester trace")
    check trace.complete "page audit exceeded its trace allowance"
    traces := traces.push (toJson (trace.operations.map (fun operation =>
      (PageMap.readObservationCodec.encode operation).map UInt8.toNat),trace.encodedBytes,trace.complete))
  let loaded ← IO.monoNanosNow
  let counts ← totals view.sources
  let digest := Sha256.hex (toJson graphs).compress.toUTF8
  if pool.isSome then
    for source in view.sources do
      let cache ← source.cache.get
      check (cache.recent.isEmpty && cache.previous.isEmpty) "shared reader retained a private page cache"
  -- A different requester gets fresh accounting and traces, while the exact
  -- immutable image and the bounded verified page pool remain retained.
  let forked ← view.fork
  for source in forked.sources do
    check ((← source.reads.get) == 0 && (← source.readBytes.get) == 0 && (← source.trace.get).isNone)
      "requesters share mutable read accounting"
  check (forked.cut == cut && forked.sources.map (·.head) == cut.heads) "fork changed the frozen boundary"
  return Json.mkObj [("pair",toJson pair),("shared",toJson pool.isSome),
    ("openNs",toJson (opened-started)),("materializeNs",toJson (loaded-opened)),
    ("openingReads",toJson opening.1),("openingBytes",toJson opening.2),
    ("totalReads",toJson counts.1),("totalBytes",toJson counts.2),
    ("openingCounters",before),("counters",← counters view.sources),
    ("graphDigest",toJson digest),("traces",toJson traces),
    ("forkAccountingPrivate",toJson true),("exactHeads",toJson cut.heads)]
def run (source root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute page audit directory required"
  IO.FS.createDirAll root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identity.exitCode == 0) "page audit runtime identity missing"
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let project ← ProjectStore.openProject (source/"work.project")
  let frozen ← read (source/"frozen-readback.json")
  let expected ← IO.ofExcept (fromJson? (frozen.getObjValD "sourceHeads") : Except String (Array PageMap.Head))
  let cut : ProjectStore.Cut := ⟨project.manifest.identity,expected⟩
  check (expected.size == 16 && cut.inScope project.manifest) "page audit omitted a frozen source"
  let pool ← PageMap.PagePool.new
  let mut rows := #[]
  for pair in [:3] do
    for shared in (if pair == 1 then [true,false] else [false,true]) do
      rows := rows.push (← trial project cut (if shared then some pool else none) pair)
      IO.FS.writeFile (root/"rows.json") ((toJson rows).pretty++"\n")
  let some first := rows[0]? | throw (IO.userError "page audit produced no reference")
  for row in rows do
    check (row.getObjValD "graphDigest" == first.getObjValD "graphDigest" &&
      row.getObjValD "traces" == first.getObjValD "traces") "page reuse changed graph bytes or read dependencies"
  let sources ← (List.range 16).toArray.mapM fun owner => project.current owner
  check (sources.map (·.head) == expected) "page audit changed original source heads"
  let report := Json.mkObj [("allPassed",toJson true),("rows",toJson rows),("pool",← pool.stats),
    ("sourceHeadsUnchanged",toJson true),("allGraphDigestsAndReadTracesEqual",toJson true),
    ("requesterAccountingPrivate",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false),("actualHookMeasured",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  let summary := rows.map fun row => Json.mkObj
    (["pair","shared","openNs","materializeNs","openingReads","openingBytes","totalReads","totalBytes","graphDigest"].map fun name => (name,row.getObjValD name))
  IO.println (report.setObjVal! "rows" (toJson summary)).compress
end Eggshell.Research.ProjectPageReuseChecks
def main (args : List String) : IO Unit := do
  let [source,root] := args | throw (IO.userError "ProjectPageReuseChecks RETAINED_SOURCE FRESH_ROOT")
  Eggshell.Research.ProjectPageReuseChecks.run (.mk source) (.mk root)
