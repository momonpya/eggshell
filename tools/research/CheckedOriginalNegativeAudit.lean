import Eggshell.Handoff
import tools.research.CheckedOriginalRecipe
open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.CanonicalSource
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejected (action : IO Unit) : IO Bool := do
  try action; return false
  catch _ => return true

private def emptyAndCorrupt : IO Json := do
  let directory ← IO.FS.realPath (← IO.FS.createTempDir)
  let cache ← PreparedOwnerArena.Cache.new
  try
    let source ← DB.PageMap.create (directory / "recipes") "negative original lookup"
    let metadata : Cache.Manifest := {
      source := source.head,implementation := Cache.implementation,payload := String.ofList (List.replicate 64 'a'),
      rows := 0,statistics := {}}
    let loaded : Shared.Loaded := ⟨metadata,source,none,cache,"empty-publication"⟩
    let deadline := (← IO.monoMsNow)+30000
    let values ← loaded.rows #["owner","owner"] deadline
    ensure (values.size == 2 && values.all (fun (_,value) => value.rows.isEmpty && value.records.isEmpty))
      "missing owner was not a valid empty projection"
    ensure (((← cache.stats).getObjValAs? Nat "loads").toOption == some 1) "negative lookup was rebuilt"
    let _ ← DB.PageMap.withWriter source fun writer => writer.put (Recipe.name "broken") (some ByteArray.empty)
    let corrupt ← DB.PageMap.pin source.directory
    let corrupted := {loaded with recipes := corrupt,identity := "corrupt-publication"}
    ensure (← rejected (do let _ ← corrupted.rows #["broken"] deadline; pure ()))
      "malformed present byte count was hidden as an empty result"
    let prior ← loaded.rows #["owner"] deadline
    ensure (prior.all (fun (_,value) => value.rows.isEmpty)) "old pinned negative result was invalidated"
    let failed : Transport.Plan := {canonicalFailure := #[("database","corrupt source")]}
    ensure (!failed.complete) "source error was reported as complete"
    let healthy : Transport.Plan := {}
    ensure healthy.complete "valid empty result was rejected"
    return Json.mkObj [("validNegative",toJson true),("corruptDescriptorRejected",toJson true),
      ("oldPinRetained",toJson true),("sourceFailureIncomplete",toJson true)]
  finally
    cache.close
    IO.FS.removeDirAll directory

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "fresh mixed-owner audit output required")
  let output : System.FilePath := .mk output
  ensure (!(← output.pathExists)) "preserve previous mixed-owner result"
  let fixtures ← emptyAndCorrupt
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let source ← DB.PageMap.pin (root / "checked-original-hook-trial/candidate/work.egg")
  let path ← Cache.directory source .database
  let some metadata ← Cache.manifestAt? source path | throw (IO.userError "actual prepared source is missing")
  let initialHead := source.head
  let some ready ← Cache.atSource? source path metadata | throw (IO.userError "actual source payload is not ready")
  let reader ← Persistence.Store.NodeReader.new source
  let owners ← (← Build.entries source).mapM fun entry => do
    let edge ← reader.outcome (← reader.locateOutcome entry.id)
    return Persistence.selectionKey edge.relation
  let owners := (hashDistinct owners.toList).toArray
  let requested := owners.push "absent-owner"
  let pool ← Shared.Pool.new
  let geometry ← ObservedRecordView.Cache.new
  try
    let result ← pool.withReady source path metadata ((← IO.monoMsNow)+30000) fun loaded _ => do
      let deadline := (← IO.monoMsNow)+30000
      let mut expected := #[]
      let mut missing := #[]
      for owner in requested do
        let descriptor ← loaded.recipes.get (Recipe.name owner)
        if descriptor.isNone then missing := missing.push owner
        expected := expected.push (owner,(← Recipe.read? loaded.recipes owner).getD ⟨#[],[]⟩)
      ensure (!missing.isEmpty) "mixed-owner regression did not include an absent canonical descriptor"
      let absent ← loaded.recipes.get (Recipe.name missing[0]!)
      ensure ((DB.PageMap.payloadSize absent).toOption.isNone) "old missing-byte-count failure did not reproduce"
      let start ← IO.monoMsNow
      let actual ← loaded.rows requested deadline
      let elapsed := (← IO.monoMsNow)-start
      ensure (actual == expected) "mixed owner projection changed the legacy valid result"
      let raw : Shared.Projection := ⟨toJson "audit",actual.map (fun (owner,value) => (owner,value.rows)),.hit,
        actual.map (fun (owner,value) => (owner,value.records))⟩
      let typed ← CheckedOriginal.fromProjection source.head.identity raw
      ensure (toJson typed.raw == toJson raw) "typed remote boundary lost generic or missing owners"
      let some original := loaded.originals | throw (IO.userError "actual original geometry index missing")
      let mut genericViews := 0
      for owner in missing do
        if let some _ ← geometry.acquire original.index source.head.identity owner deadline then
          genericViews := genericViews+1
      ensure (genericViews > 0) "mixed source did not exercise general original-output geometry"
      return Json.mkObj [("requestedOwners",toJson requested.size),("emptyCanonicalOwners",toJson missing.size),
        ("genericOriginalViews",toJson genericViews),("allSourceOwners",toJson owners.size),
        ("elapsedRowsMs",toJson elapsed),("sameCompleteProjection",toJson true)]
    let stats ← pool.stats
    pool.close
    ensure ((← DB.PageMap.pin source.directory).head == initialHead) "mixed regression changed original source"
    IO.FS.writeFile output (Json.mkObj [("source",toJson initialHead),("canonicalRows",toJson ready.metadata.rows),
      ("fixtures",fixtures),("mixed",result),("pool",stats),("sourceUnchanged",toJson true),
      ("actualHooks",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
    IO.println result.compress
  finally pool.close
