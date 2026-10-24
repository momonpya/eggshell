import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Journal

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def policy : IO Unit := do
  let month := ObservationAge.monthMs
  let received := 1000000000
  check (month == 2592000000) "default advisory interval changed"
  for interval in [0,1,month] do
    for elapsed in [0,1,month-1,month,month+1] do
      let age := ObservationAge.assess (some (received+elapsed)) (some received) interval
      check (age.status == if elapsed < interval then .recent else .expired)
        "receipt-age boundary is not half-open"
      check (age.receivedUnixMs == some received) "assessment refreshed the acquisition date"
  check ((ObservationAge.assess (some (received-1)) (some received)).status == .clockSkew &&
    (ObservationAge.assess none (some received)).status == .unknown &&
    (ObservationAge.assess (some received) none).status == .unknown &&
    (ObservationAge.assess (some received) (some 0)).status == .unknown)
    "unknown or future dates became fresh"
  let clock : Clock := ⟨String.ofList (List.replicate 64 'a'),123⟩
  let event : Entry := ⟨clock,.finish ⟨"session","turn","tool"⟩ "mcp__any__read" "{}" "{}" none,none⟩
  let oldJson := Json.mkObj [("clock",toJson clock),("payload",toJson event.payload)]
  let decoded ← IO.ofExcept (fromJson? (α := Entry) oldJson)
  check (decoded == event && toJson decoded == oldJson)
    "an event without a receipt date cannot remain canonical and unknown"
  let known := {event with receivedUnixMs := some received}
  let retried := {known with receivedUnixMs := some (received+month),clock := {clock with nanos := 999}}
  check ((retainFirst known retried).toOption == some known)
    "a retry refreshed the first acquisition date"
  check ((retainFirst event known).toOption == some event)
    "retry fabricated a receipt date for an unknown original"
  let origin : Provenance.Origin := ⟨7,⟨"session","turn","tool"⟩,clock.domain,1,2,none⟩
  let oldOrigin := Json.mkObj [("owner",toJson origin.owner),("occurrence",toJson origin.occurrence),
    ("domain",toJson origin.domain),("started",toJson origin.started),("finished",toJson origin.finished)]
  let decoded ← IO.ofExcept (fromJson? (α := Provenance.Origin) oldOrigin)
  check (decoded == origin && toJson decoded == oldOrigin)
    "old provenance gained a synthetic timestamp or changed its canonical digest"
  let stamped := Json.mkObj [("_eggshell_received_unix_ms",toJson received)]
  check (Live.receivedUnixMs? stamped == some received && Live.receivedUnixMs? (Json.mkObj []) == none &&
      Live.receivedUnixMs? (Json.mkObj [("_eggshell_received_unix_ms",toJson (0 : Nat))]) == none)
    "native ingress did not preserve an actual positive receipt time"
  let some before ← ObservationAge.now | throw (IO.userError "missing system wall clock")
  let some after ← ObservationAge.now | throw (IO.userError "missing system wall clock")
  check (before > 1700000000000 && after ≥ before && after-before < 10000)
    "system acquisition clock is not an epoch millisecond clock"

def main (_ : List String) : IO Unit := do
  policy
  IO.println "observation age passed: 30-day and provider interval boundaries, unknown/skew, canonical undated records, immutable retries, native receipt extraction and system epoch clock"
