import Eggshell.CanonicalSourcePrepared
import tools.research.BindingPageScan
open Lean Eggshell Eggshell.DB Eggshell.Synapses

namespace Eggshell.Research.BindingCacheCensus
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)

def same (left right : IndexedBindings.Resolved) : Bool :=
  left.complete == right.complete && left.requests == right.requests &&
  left.bytes == right.bytes && left.inspected == right.inspected &&
  left.unresolved == right.unresolved && left.unusable == right.unusable &&
  left.rows.size == right.rows.size &&
  left.rows.toArray.all (fun (source,rows) => right.rows[source]? == some rows)

def prepared (source : PageMap.Snapshot) : IO (System.FilePath × CanonicalSource.Cache.Manifest) := do
  for storage in [Sidecar.Storage.database,.user] do
    if let some ready ← CanonicalSource.Cache.open? source storage then
      return (← CanonicalSource.Cache.directory source storage,ready.metadata)
  throw (IO.userError "the original source is not already prepared; census must not warm it")

def run (directory report : System.FilePath) : IO Unit := do
  check (!(← report.pathExists)) "preserve preceding cache census"
  let source ← PageMap.pin directory
  let (path,metadata) ← prepared source
  let pool ← CanonicalSource.Shared.Pool.new
  try
    pool.withReady source path metadata ((← IO.monoMsNow)+30000) fun loaded _ => do
      let some reader := loaded.originals | throw (IO.userError "prepared source has no original binding index")
      -- Independent enumeration supplies the real source-posting domain. It
      -- cannot prime the service-wide cache measured in the following passes.
      let independent ← reader.index.forkReader
      let (wanted,owners,count,logicalBytes) ← independent.foldRange ⟨"binding:","binding;"⟩
        (fun (wanted,owners,count,logicalBytes) (key,bytes) => do
          let some bytes := bytes | return (wanted,owners,count,logicalBytes)
          let binding ← Index.decodeBinding bytes
          check (binding.read.valid && key == "binding:"++Index.contentKey binding.read.source++":"++binding.fact)
            "census found an invalid or misaddressed original binding"
          return (wanted.insert binding.read.source,owners.insert binding.read.binding.owner,count+1,logicalBytes+bytes.size))
        (({} : Std.HashSet Range),({} : Std.HashSet String),(0 : Nat),(0 : Nat))
      let wanted := wanted.toArray.qsort fun a b => Index.contentKey a < Index.contentKey b
      check (!wanted.isEmpty) "real original binding domain is empty"
      let mut results := #[]
      let mut expected : Option IndexedBindings.Resolved := none
      for pass in [:5] do
        let before ← pool.pages.stats
        let reads ← reader.index.reads.get
        let bytes ← reader.index.readBytes.get
        let began ← IO.monoMsNow
        let value ← BindingPageScan.resolveReport reader wanted owners (began+30000)
        let elapsed := (← IO.monoMsNow)-began
        check value.resolved.complete "census exceeded the existing complete scan contract"
        if let some previous := expected then check (same previous value.resolved) "hot scan changed bindings, order or logical counters"
        expected := some value.resolved
        let after ← pool.pages.stats
        let resident ← match pool.pages with
          | .reader _ => throw (IO.userError "census no longer exercises the actual shared owner path")
          | .owner state => state.atomically do
            let state ← get
            let entries := state.cache.recent.toArray++state.cache.previous.toArray.filter
              (fun (key,_) => !state.cache.recent.contains key)
            return Json.mkObj [("uniquePages",toJson entries.size),
              ("encodedBytes",toJson (entries.foldl (fun sum (_,page) => sum+page.ref.bytes) 0)),
              ("generationSlots",toJson PageMap.sharedGenerationSlots)]
        results := results.push (Json.mkObj [("pass",toJson pass),("elapsedMs",toJson elapsed),
          ("physicalPageReads",toJson ((← reader.index.reads.get)-reads)),
          ("physicalBytes",toJson ((← reader.index.readBytes.get)-bytes)),
          ("traversedPages",toJson value.pages),("traversedLeaves",toJson value.leaves),
          ("before",before),("after",after),("resident",resident),
          ("inspected",toJson value.resolved.inspected),("logicalBytes",toJson value.resolved.bytes),
          ("resolvedRanges",toJson value.resolved.rows.size),("unresolved",toJson value.resolved.unresolved)])
        IO.println s!"pass={pass} ms={elapsed} pages={value.pages} physical={(← reader.index.reads.get)-reads}"
      check ((← PageMap.pin directory).head == source.head) "cache census changed the original DB"
      IO.FS.writeFile report (Json.mkObj [("originalHead",toJson source.head),("prepared",toJson metadata),
        ("indexHead",toJson reader.index.head),("sourcePostings",toJson count),
        ("sourcePostingBytes",toJson logicalBytes),("allUniqueOriginalRanges",toJson wanted.size),
        ("allowedOwners",toJson owners.size),("passes",toJson results),
        ("allBindingsAndOrderExact",toJson true),("preparedWasReadOnly",toJson true),
        ("allPostingDomainNotActualQuestionSubset",toJson true),("actualHookCalls",toJson (0 : Nat)),
        ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  finally pool.close
end Eggshell.Research.BindingCacheCensus

def main (args : List String) : IO Unit := do
  let [source,report] := args | throw (IO.userError "binding cache census ORIGINAL OUTPUT")
  Eggshell.Research.BindingCacheCensus.run (.mk source) (.mk report)
