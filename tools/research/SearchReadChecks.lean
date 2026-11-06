module
public import Eggshell.Worker
public import Eggshell.ContractAudit
public import tools.research.SearchReadCut
@[expose] public section
namespace Eggshell.Research.SearchReadChecks
open Lean Eggshell.Plugin.Worker
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

#print axioms SearchReadCut.advanced_bounded
#print axioms SearchReadCut.late_first_refused
#print axioms SearchReadCut.late_final_refused
#print axioms SearchReadCut.repeated_ready_refused
#print axioms SearchReadCut.foreign_first_refused
#print axioms SearchReadCut.foreign_final_refused

private def occurrences (target : Name) : Expr → Nat
  | .const name _ => if name == target then 1 else 0
  | .app f x => occurrences target f+occurrences target x
  | .lam _ ty body _ | .forallE _ ty body _ => occurrences target ty+occurrences target body
  | .letE _ ty value body _ => occurrences target ty+occurrences target value+occurrences target body
  | .mdata _ value | .proj _ _ value => occurrences target value
  | _ => 0
run_cmd do
  let env ← getEnv
  let body (name : Name) := do
    let some value := (env.find? name).bind (·.value?) | throwError "missing actual read implementation {name}"
    pure value
  let reading ← body ``readSearchReply
  unless occurrences ``readSearchFrame reading == 2 &&
      occurrences ``SearchReadCut.first reading == 1 && occurrences ``SearchReadCut.final reading == 1 do
    throwError "actual read must consume one first frame and at most one final frame through the checked protocol"
  let mut pending := [``readSearchReply,``awaitSearchFrame,``SearchReadCut.first,``SearchReadCut.final]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","IO.Ref.","IO.mkRef","IO.Promise.","IO.Prim.mkRef","IO.Prim.Ref."].any
        (fun stem => name.toString.startsWith stem) then
      throwError "owned search read reaches shared mutable scheduling state {name}"
    -- Native task completion, the pipe and the monotonic clock remain explicit
    -- OS boundaries. The deadline protocol itself has no such operations.
    if [``retire,``IO.asTask,``IO.wait].contains name then continue
    if let some value := (env.find? name).bind (·.value?) then pending := value.getUsedConstants.toList++pending
  logInfo m!"Actual search read: no deadline mutex/ref/promise; {seen.size} dependencies audited (pipe retirement is the owned cleanup boundary)"
  let mut purePending := [``SearchReadCut.first,``SearchReadCut.final]
  let mut pureSeen : Std.HashSet Name := {}
  while let some name := purePending.head? do
    purePending := purePending.tail!
    if pureSeen.contains name then continue
    pureSeen := pureSeen.insert name
    if ["Std.Mutex.","IO.","BaseIO.","EIO."].any (fun stem => name.toString.startsWith stem) then
      throwError "pure phase transition reaches IO {name}"
    if let some value := (env.find? name).bind (·.value?) then purePending := value.getUsedConstants.toList++purePending
  logInfo m!"Pure phase transitions: {pureSeen.size} dependencies without IO"

def original : Eggshell.Plugin.Handoff := {
  text := "原文の条件: if (kind == InputKind::HLSL) { return; }\n末尾も保存。"
  reason := "advisory",deliveredGraphs := ["frozen-graph"],completed := 0,advisory := 1,
  localUnions := 0,coveredFragments := ["original-fragment"],blocksCurrent := false }

def wirePayload (mode : String) (identity : SearchIdentity) : Json := Id.run do
  let ready := toJson (SearchFrame.ready identity)
  let reply := toJson (SearchFrame.reply identity none)
  let frames := match mode with
    | "direct" => #[reply]
    | "body" => #[toJson (SearchFrame.reply identity (some original))]
    | "ready" | "delayed-final" => #[ready,reply]
    | "repeated" => #[ready,ready]
    | "foreign" => #[toJson (SearchFrame.reply {identity with turn := identity.turn++"/foreign"} none)]
    | _ => #[]
  return Json.mkObj [("frames",toJson frames),("pauseMs",toJson
    (if mode == "blocked" then 30000 else if mode == "delayed-final" then 750 else 0 : Nat))]

/-- Pre-existing pipe ownership is the ordinary Slot reuse path. Only the
peer is small; exchangeSlot and all waits/retirement are the product code. -/
def wireSlot (wire : System.FilePath) : IO Slot := do
  let child ← IO.Process.spawn {cmd := wire.toString,stdin := .piped,stdout := .piped,stderr := .null,setsid := true}
  return ⟨← Std.Mutex.new (),← Std.Mutex.new (.open (some child))⟩

def run (root wire : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh control root required"
  IO.FS.createDirAll root
  let expected : SearchIdentity := ⟨"frozen-turn",7,1000,some "frozen-receipt"⟩
  let identities := #[expected,{expected with turn := "foreign"},{expected with epoch := 8},
    {expected with deadline := 1001},{expected with receipt := none}]
  let mut comparisons := 0
  for actual in identities do
    for cutoff in #[0,1,10,999,1000,1001] do
      for arrived in #[0,1,9,10,998,999,1000,1001] do
        for finishReady in #[false,true] do
          let accepts := actual == expected && arrived < cutoff
          let first := SearchReadCut.first expected finishReady cutoff arrived
          let direct := first (.reply actual (17 : Nat))
          check (direct.isOk == accepts) "direct reply changed the exact acceptance predicate"
          let progress := first (.ready actual : SearchReadCut.Frame Nat)
          check (progress.isOk == accepts) "ready changed the exact acceptance predicate"
          if let .ok (.final next) := progress then
            check (next == readyDeadline expected actual finishReady cutoff arrived && next ≤ expected.deadline)
              "ready changed its scheduling result or exceeded the upstream deadline"
          check ((SearchReadCut.final expected cutoff arrived (.reply actual (17 : Nat))).isOk == accepts)
            "final reply changed the exact acceptance predicate"
          comparisons := comparisons+3
  let began ← IO.monoMsNow
  let actors ← (Array.range 80).mapM fun index => IO.asTask (do
    let slot ← wireSlot wire
    try
      for mode in #["direct","ready","body"] do
        let now ← IO.monoMsNow
        let deadline := now+15000
        let identity : SearchIdentity := ⟨"parallel-"++toString index,0,deadline,none⟩
        let ready ← IO.mkRef (0 : Nat)
        let policy : SearchPolicy := {identity,finishReady := true,onReady := fun _ => ready.modify (·+1)}
        let some window := OpenWindow.check deadline now | throw (IO.userError "control window closed")
        let reply ← exchangeSlot slot "search-read-fixture" (wirePayload mode identity) deadline (some policy) window
        check (reply == some (if mode == "body" then toJson original else Json.null))
          "search reply changed its exact original payload or valid empty result"
        check ((← ready.get) == (if mode == "ready" then 1 else 0)) "ready callback changed count"
    finally closeSlot slot) .dedicated
  try
    for actor in actors do
      match ← IO.wait actor with
      | .ok _ => pure ()
      | .error error => throw error
  finally
    for actor in actors do IO.cancel actor
    for actor in actors do discard <| IO.wait actor
  let elapsed := (← IO.monoMsNow)-began
  -- A warmed pipe delivers ready before the phase cutoff and the reply after
  -- it. Only the explicit finishReady policy may use the upstream window.
  for finishReady in #[true,false] do
    let slot ← wireSlot wire
    try
      let now ← IO.monoMsNow
      let identity : SearchIdentity := ⟨"warm",0,now+5000,none⟩
      let some window := OpenWindow.check (now+5000) now | throw (IO.userError "warm window closed")
      discard <| exchangeSlot slot "search-read-fixture" (wirePayload "direct" identity) (now+5000) (some {identity}) window
      let now ← IO.monoMsNow
      let cutoff := now+500
      let identity : SearchIdentity := ⟨"phase-change",0,now+5000,none⟩
      let some window := OpenWindow.check cutoff now | throw (IO.userError "phase window closed")
      let reply ← exchangeSlot slot "search-read-fixture" (wirePayload "delayed-final" identity) cutoff (some {identity,finishReady}) window
      check (reply.isSome == finishReady) "ready failed to preserve the explicit phase scheduling policy"
    finally closeSlot slot
  for mode in #["repeated","foreign","blocked"] do
    let slot ← wireSlot wire
    let now ← IO.monoMsNow
    let deadline := now+(if mode == "blocked" then 250 else 5000)
    let identity : SearchIdentity := ⟨mode,0,deadline,none⟩
    let some window := OpenWindow.check deadline now | throw (IO.userError "negative control window closed")
    try
      let reply ← exchangeSlot slot "search-read-fixture" (wirePayload mode identity) deadline (some {identity,finishReady := true}) window
      check reply.isNone "invalid/expired transport was accepted"
      let empty ← slot.child.atomically do
        match ← get with
        | .open none | .closed => pure true
        | _ => pure false
      check empty "failed transport kept its child"
    finally closeSlot slot
  let slot ← wireSlot wire
  let actor ← IO.asTask (do
    let now ← IO.monoMsNow
    let deadline := now+15000
    let identity : SearchIdentity := ⟨"cancel",0,deadline,none⟩
    let some window := OpenWindow.check deadline now | throw (IO.userError "cancel window closed")
    exchangeSlot slot "search-read-fixture" (wirePayload "blocked" identity) deadline (some {identity}) window) .dedicated
  try
    let startDeadline := (← IO.monoMsNow)+5000
    repeat
      let started ← slot.child.atomically do
        match ← get with
        | .open (some _) => pure true
        | _ => pure false
      if started then break
      check ((← IO.monoMsNow) < startDeadline) "cancel control did not start its owned child"
      IO.sleep 1
    IO.cancel actor
    match ← IO.wait actor with
    | .ok reply => check reply.isNone "cancelled read produced a completed reply"
    | .error error => throw error
    let empty ← slot.child.atomically do
      match ← get with
      | .open none | .closed => pure true
      | _ => pure false
    check empty "cancellation kept its child"
  finally
    IO.cancel actor
    discard <| IO.wait actor
    closeSlot slot
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("policyComparisons",toJson comparisons),
    ("parallelRequests",toJson (80 : Nat)),("nativeExchanges",toJson (240 : Nat)),("elapsedMs",toJson elapsed),
    ("validEmptyReplyAndReadyCallbacksPreserved",toJson true),("invalidAndTimeoutRetiredOwnedChild",toJson true),
    ("phaseExtensionOnlyWhenAuthorized",toJson true),("cancelledReadJoined",toJson true),
    ("sharedDeadlineMutexRemoved",toJson true),("replacementRefOrPromise",toJson false),
    ("wholeSearchLockFree",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.SearchReadChecks
