module
public import Eggshell.PluginHooks
public import tools.research.PositiveProjection
@[expose] public section

namespace Eggshell.Research.PositiveProjectionChecks
open Lean Plugin Synapses

def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)

theorem shared_ack_has_native_origin (part : DeliveryPart) (shared : CanonicalSource.Delivery.Part)
    (noContext : part.context = none) (sharedPart : part.shared = some shared)
    (rendered : part.text = shared.render) (keys : part.keys = shared.keys)
    (read : Read) (selected : read ∈ part.acknowledgedReads) :
    read ∈ part.evidence ∧ read.valid = true ∧
    ∃ row ∈ shared.rows, ∃ origin ∈ row.origins,
      read.binding = origin.binding ∧ read.occurrence = origin.occurrence ∧
      read.source = ⟨.file row.key.file,row.key.line,row.key.line⟩ := by
  have present : read ∈ PositiveProjection.sharedReads shared.rows part.evidence := by
    have selected' : read ∈ PositiveProjection.select (PositiveProjection.prepareShared shared.rows) part.evidence := by
      simpa [DeliveryPart.acknowledgedReads,DeliveryPart.preparedAcknowledgment,
        noContext,sharedPart,rendered,keys] using selected
    simpa only [PositiveProjection.prepared_shared_exact] using selected'
  exact ⟨(PositiveProjection.selected_was_verified _ _ _ present).1,
    (PositiveProjection.selected_was_verified _ _ _ present).2,
    PositiveProjection.selected_has_native_origin _ _ _ present⟩

#print axioms shared_ack_has_native_origin

def file : File := ⟨"input.txt",String.ofList (List.replicate 64 'a'),10⟩
def occurrence : Occurrence := ⟨"recording","turn","read"⟩
def binding (owner : String) (first limit : Nat) : Binding := ⟨"project",owner,"work",first,limit⟩
def sourceRead (owner : String) (line first limit : Nat) : Read :=
  ⟨occurrence,⟨.file file,line,line⟩,binding owner first limit,#[]⟩
def firstRead := sourceRead "native" 1 0 5
def secondRead := sourceRead "native" 2 6 10
def row (line : Nat) (code : String) (origins : Array Read) : CanonicalSource.StoredRow :=
  ⟨⟨file,line⟩,code,origins.map fun read => ⟨read.occurrence,read.binding⟩⟩
def sharedPart (rows : Array CanonicalSource.StoredRow) : IO DeliveryPart := do
  let some shared := CanonicalSource.Delivery.Part.check? rows | throw (IO.userError "empty fixture")
  return {keys := shared.keys,text := shared.render,shared := some shared}
def contextPart (original : String) : DeliveryPart :=
  let context : ContextDelivery := {
    owner := "native"
    outcome := "outcome"
    sourceChars := 10
    cues := [(0,original.length)]
    leading := ""
    trailing := ""
    fragments := [⟨0,original,false,none⟩]}
  {keys := context.keys,text := context.render,context := some context}
def handoff (parts : List DeliveryPart) : Handoff :=
  let packet : DeliveryPacket := {header := "",footer := "",parts}
  {text := packet.render,reason := "fixture",deliveredGraphs := parts.flatMap (·.keys),
    completed := 0,advisory := parts.length,localUnions := 0,coveredFragments := [],blocksCurrent := false,packet := some packet}
def native : Extraction.Document := {
  owner := "native"
  work := "work"
  workText := none
  source := some "alpha\nbeta"
  native := true
  occurrences := #[occurrence]
  files := #[file]}
def plan : Transport.Plan := {documents := #[native],rows := #[firstRead,secondRead]}

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh positive projection controls required"
  IO.FS.createDirAll root
  let missing := sourceRead "unavailable" 1 0 5
  let shared ← sharedPart #[row 1 "alpha" #[firstRead,missing],row 2 "beta" #[secondRead]]
  let original := handoff [shared,contextPart "alpha",{keys := ["g:advisory"],text := "advisory only"}]
  let (prepared,receipt) := original.prepareDelivery plan
  check (prepared.val.text == original.text && prepared.val.deliveredGraphs == original.deliveredGraphs &&
    prepared.val.completed == 0 && !prepared.val.blocksCurrent) "projection changed body, keys or authority"
  let some captured := prepared.val.capturedPacket? | throw (IO.userError "fixture packet lost its actual body")
  let some checkedShared := captured.packet.parts.head? | throw (IO.userError "fixture lost shared part")
  check (!checkedShared.projected && !checkedShared.projectionComplete && checkedShared.evidence.size == 2)
    "fixture must retain two checked witnesses beside the unsupported origin"
  let projected := prepared.val.acknowledgmentProjection
  check (projected.verified && !projected.complete && projected.rows.size == 3 && projected.bindings.size == 1)
    "unrelated incomplete parts still veto positive original evidence"
  check (projected.rows.all fun entry => entry.database == "project" &&
    (entry.source == firstRead.source || entry.source == secondRead.source)) "foreign projection escaped"
  let some remaining := checkedShared.remaining [CanonicalSource.Delivery.rowKey ⟨file,2⟩] |
    throw (IO.userError "reconciliation removed all rows")
  let remainder := (handoff [remaining]).acknowledgmentProjection
  check (remainder.verified && !remainder.complete && remainder.rows.size == 1 && (remainder.rows[0]?.map (·.source)) == some firstRead.source)
    "subtracted original evidence survived reconciliation"
  let noWitness := (handoff [{checkedShared with evidence := #[]}]).acknowledgmentProjection
  check (noWitness.verified && !noWitness.complete && noWitness.rows.isEmpty && noWitness.bindings.isEmpty)
    "packet metadata manufactured a source witness"
  let changed := {prepared.val with text := prepared.val.text++"changed"}
  check (!changed.acknowledgmentProjection.complete && changed.acknowledgmentProjection.rows.isEmpty)
    "changed actual body retained an original projection"
  let wrongKeys := {checkedShared with keys := []}
  check ((handoff [wrongKeys]).acknowledgmentProjection.rows.isEmpty) "changed part keys admitted evidence"
  let wrongText := {checkedShared with text := "substitute"}
  check ((handoff [wrongText]).acknowledgmentProjection.rows.isEmpty) "changed part text admitted evidence"
  let corruptRows ← sharedPart #[row 1 "not alpha" #[firstRead]]
  let corrupt := ((handoff [corruptRows]).prepareDelivery plan).1.val
  check (corrupt.acknowledgmentProjection.rows.isEmpty) "unverified original spelling was confirmed"
  let foreign ← sharedPart #[row 1 "alpha" #[{firstRead with binding := {firstRead.binding with work := "other"}}]]
  let foreign := ((handoff [foreign]).prepareDelivery plan).1.val
  check (foreign.acknowledgmentProjection.rows.isEmpty) "foreign Work acquired a source-byte witness"
  check (!(PositiveProjection.checked #[⟨"",firstRead.source⟩] #[] true).verified) "invalid projected project accepted"
  let some reference ← DeliveryLedger.confirm "positive-original" 0 none projected |
    throw (IO.userError "positive projection did not produce an ACK ledger")
  let saved ← DeliveryLedger.lookup reference "project"
  check (saved.size == 2 && saved.contains firstRead.source && saved.contains secondRead.source)
    "confirmed ledger lost or invented original ranges"
  let other ← DeliveryLedger.lookup reference "other-project"
  check other.isEmpty "project scope crossed at ACK lookup"
  let bindings ← DeliveryLedger.lookupBindings reference "project" (Std.HashSet.ofList [("native","work")])
  check (bindings == #[firstRead.binding]) "native binding projection changed"
  let absent ← DeliveryLedger.confirm "positive-empty" 0 none noWitness
  check absent.isNone "no-witness advisory created a ledger"
  -- Larger than the failed real packet. This is a metadata/performance
  -- control, not a source-byte witness and never written to the ACK ledger.
  let stressReads := (Array.range 12000).map fun index => sourceRead "native" (index+1) 0 5
  let stressPart ← sharedPart (stressReads.map fun read => row read.source.first "alpha" #[read])
  let stressPart := {stressPart with evidence := stressReads++stressReads,projected := false}
  let input ← IO.mkRef stressPart
  let began ← IO.monoMsNow
  let observed ← input.get
  let selected ← IO.mkRef observed.acknowledgedReads.size
  let selected ← selected.get
  let preparedMs := (← IO.monoMsNow)-began
  check (selected == 24000 && preparedMs < 3000) "actual prepared selector repeated per-read index/render preparation"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("allPassed",toJson true),
    ("checkedEvidence",toJson checkedShared.evidence.size),("unverifiedOriginStillExcluded",toJson true),
    ("ackRowsBeforeDedup",toJson projected.rows.size),("retainedRows",toJson saved.size),
    ("reconciledRows",toJson remainder.rows.size),("nativeBindings",toJson bindings.size),
    ("bodyAndAuthorityUnchanged",toJson true),("partialAndAdvisoryCannotManufactureWitnesses",toJson true),
    ("changedBodyKeysSpellingWorkAndProjectRejected",toJson true),("prepareReceipt",receipt),
    ("preparedStressRows",toJson (12000 : Nat)),("preparedStressEvidence",toJson selected),
    ("preparedStressMs",toJson preparedMs),("metadataOnlyStressNotAByteWitness",toJson true),
    ("actualNewHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.PositiveProjectionChecks
