module

public import Eggshell.SynapseJournal

@[expose] public section

namespace Eggshell.Synapses.Live
open Lean

def clock? (input : Json) : Option Journal.Clock := do
  let domain ← (input.getObjValAs? String "_eggshell_synapse_clock").toOption
  let nanos ← (input.getObjValAs? Nat "_eggshell_synapse_nanos").toOption
  if digest domain then some ⟨domain, nanos⟩ else none

def receivedUnixMs? (input : Json) : Option Nat :=
  (input.getObjValAs? Nat "_eggshell_received_unix_ms").toOption.filter (0 < ·)

def attempt (action : IO Unit) : IO Unit := do
  try action
  catch error => IO.eprintln s!"Eggshell retained unknown synaptic ingress: {error}"

def contextClock (clock : Journal.Clock) (epoch : Nat) : Journal.Clock :=
  {clock with domain := Sha256.hex ((clock.domain ++ ":" ++ toString epoch).toUTF8)}

theorem context_clock_preserves_observed_time (clock : Journal.Clock) (epoch : Nat) :
    (contextClock clock epoch).nanos = clock.nanos := rfl

def confidencePath (files : Plugin.SessionFiles) : System.FilePath :=
  files.directory / "unconfirmed-delivery"

/-- An expired/rejected offer may have reached stdout without its ACK.
Keep uncertainty until native context is discarded rather than calling it absent. -/
def unconfirmed (files : Plugin.SessionFiles) : IO Unit := do
  FileSystem.immutableBytes (confidencePath files) ByteArray.empty

def reset (files : Plugin.SessionFiles) : IO Unit := do
  if ← (confidencePath files).pathExists then IO.FS.removeFile (confidencePath files)

def uncertain (files : Plugin.SessionFiles) (state : Plugin.ThreadState) : IO Bool := do
  return !state.offers.isEmpty || (← (confidencePath files).pathExists)

def observe (pending : Plugin.PendingTurn) (make : DB.PageMap.Snapshot → IO Journal.Entry) : IO Unit := do
  for path in pending.read.eraseDups do
    try
      let some source ← DB.PageMap.open? (.mk path) | continue
      let _ ← Journal.append source (← make source)
      Journal.register source (pending.write == some path)
    catch error => IO.eprintln s!"Eggshell retained unknown synaptic ingress: {error}"

def start (input : Json) (files : Plugin.SessionFiles) (pending : Plugin.PendingTurn)
    (state : Plugin.ThreadState) (tool : Plugin.ToolEvent) : IO Unit := do
  let some clock := clock? input | return
  let clock := contextClock clock state.epoch
  let occurrence : Occurrence := ⟨pending.sessionId, pending.turnId, tool.useId⟩
  let query := Sha256.hex pending.prompt.toUTF8
  let unknown ← uncertain files state
  observe pending fun source => do
    let known ← Journal.knowledge source state.deliveredGraphs unknown pending.write
    return ⟨clock, .start occurrence (Plugin.canonicalToolWork tool) query known, receivedUnixMs? input⟩

def finish (input : Json) (pending : Plugin.PendingTurn) (tool : Plugin.ToolEvent) : IO Unit := do
  let some clock := clock? input | return
  let files ← Plugin.sessionFiles pending.sessionId
  let some state ← (Plugin.readJson? files.state Plugin.stateJsonDefaults : IO (Option Plugin.ThreadState)) | return
  let clock := contextClock clock state.epoch
  let occurrence : Occurrence := ⟨pending.sessionId, pending.turnId, tool.useId⟩
  observe pending fun _ => pure ⟨clock, .finish occurrence tool.name
    (Plugin.canonicalJson tool.input) (Plugin.canonicalJson tool.response) pending.write, receivedUnixMs? input⟩

/-- Stop supplies final text, not a native agent-message id. Its observed
origin is the hook's session/turn, explicitly distinct from a tool occurrence. -/
def answer (input : Json) (files : Plugin.SessionFiles) (pending : Plugin.PendingTurn)
    (state : Plugin.ThreadState) : IO Unit := do
  let some clock := clock? input | return
  let clock := contextClock clock state.epoch
  let some text := pending.finalMessage | return
  let occurrence : Occurrence := ⟨pending.sessionId, pending.turnId, "hook-stop:" ++ pending.turnId⟩
  let query := Sha256.hex pending.prompt.toUTF8
  let unknown ← uncertain files state
  observe pending fun source => do
    let known ← Journal.knowledge source state.deliveredGraphs unknown pending.write
    return ⟨clock, .answer occurrence query text known, receivedUnixMs? input⟩

end Eggshell.Synapses.Live
