module

public import Eggshell.PluginHooks
public import Eggshell.PublicationClient
public import Eggshell.Warm

@[expose] public section

namespace Eggshell.Plugin
open Lean

def controlUsage : String :=
  "egg                     show this project's profile and save target\n" ++
  "egg init                initialize project settings\n" ++
  "egg inspect             show resolved DB paths and publication heads\n" ++
  "egg doctor              check configuration and index readiness\n" ++
  "egg warm [DB|PATH]       prepare saved memory for reuse\n" ++
  "egg graph / why         show this chat's delivered history / selection reason\n" ++
  "egg diff                preview the staged save\n" ++
  "\nCurrent-chat controls (run through Codex ! shell UI):\n" ++
  "egg on / off            enable / disable memory for this chat\n" ++
  "egg use PROFILE         select this chat's profile\n" ++
  "egg next PROFILE        select a profile for the next turn\n" ++
  "egg keep                save to the DB bound when the turn was recorded\n" ++
  "egg drop                clear the staged turn; keep saved work and queued saves\n" ++
  "\nLow-level graph diagnostics:\n" ++
  "egg debug graph VALUES | class VALUE | find TEXT\n" ++
  "egg debug union LEFT RIGHT | split UNION\n" ++
  "egg debug next-graph auto|none|VALUES"

def diagnosticState : IO (Option ThreadState) := do
  match ← IO.getEnv "CODEX_THREAD_ID" with
  | none => pure none
  | some id => readJson? (← sessionFiles id).state stateJsonDefaults

def cacheSources (egg : Config.Egg) : IO (Array DB.PageMap.Snapshot) := do
  if ← (egg.path/"project").pathExists then
    let project ← ProjectStore.openProject egg.path
    return (← ProjectStore.pin project ((← IO.monoMsNow)+29000)).sources
  return (← DB.PageMap.open? egg.path).toArray

def sourceCacheStatus (snapshot : DB.PageMap.Snapshot) (command : Option (List String)) : IO Json := do
  let fields := [("source",toJson snapshot.head.identity)]
  try
    let some command := command | do
      let lexical ← RetrievalResearch.Index.ready snapshot
      let windows := (← WindowOwners.openShared? snapshot).isSome
      let canonical ← Synapses.CanonicalSource.Cache.ready snapshot
      return Json.mkObj (fields++[("state",toJson (if lexical && windows && canonical then "warm" else "cold")),
        ("mode",toJson "lexical-only")])
    let options ← Warm.options snapshot command
    let inspected ← Warm.inspect snapshot options
    let state := if inspected.coverage.invalid > 0 then "invalid"
      else if inspected.coverage.missing > 0 then "cold" else "warm"
    pure (Json.mkObj (fields ++ [("state", toJson state), ("coverage", toJson inspected.coverage)]))
  catch error => pure (Json.mkObj (fields ++ [("state", toJson "error"), ("reason", toJson error.toString)]))

def databaseCacheStatus (egg : Config.Egg) (command : Option (List String)) : IO Json := do
  let fields := [("name",toJson egg.name),("path",toJson egg.path.toString)]
  try
    let sources ← cacheSources egg
    let statuses ← sources.mapM (sourceCacheStatus · command)
    let state := if sources.isEmpty then "absent"
      else if statuses.all (fun status => (status.getObjValAs? String "state").toOption == some "warm") then "warm"
      else "pending"
    return Json.mkObj (fields++[("state",toJson state),("sources",toJson statuses)])
  catch error => return Json.mkObj (fields++[("state",toJson "error"),("reason",toJson error.toString)])

/-- Inspect configuration without creating session state, writing memory, or
    starting search or model inference. Cache coverage counts live DB windows.
    Installed/configured is not proof that native hooks ran. -/
def doctor : IO String := do
  let config ← (← Config.load (← IO.currentDir)).mapM withDefaultMatcher
  let state ← diagnosticState
  let mut fields := [("runtime", Lean.toJson "installed"),
    ("hook_trust", Lean.toJson "review /hooks in Codex"),
    ("session_state_present", Lean.toJson state.isSome),
    ("handoff_observed", Lean.toJson (state.any (! ·.lastHandoff.isEmpty)))]
  match config with
  | none => fields := fields ++ [("configuration", Lean.toJson "missing"),
      ("next_step", Lean.toJson "Set up Eggshell for this project.")]
  | some config =>
      let profile := state.map (·.profile) |>.getD config.defaultProfile
      let selection ← IO.ofExcept (Config.resolve config profile)
      let mode := if state.any (! ·.enabled) ||
          (selection.read.isEmpty && selection.write.isNone) then "off"
        else if selection.write.isNone then "read-only" else "read/write"
      fields := fields ++ [("configuration", Lean.toJson "ready"),
        ("config", Lean.toJson config.source.toString),
        ("profile", Lean.toJson profile), ("memory", Lean.toJson mode),
        ("write",toJson (selection.write.map (·.path.toString))),
        ("handoff_chars",toJson selection.handoffChars),
        ("databases", toJson (← selection.read.mapM (databaseCacheStatus · selection.semanticMatcher))),
        ("next_step", Lean.toJson
          "Review /hooks and start a new chat. Verify saving and delivery with the two-chat example.")]
  pure (Lean.Json.mkObj fields |>.compress)

/-- Explicit warming is available from an ordinary terminal, including a DB
imported without a project config. It does not need or mutate chat state. -/
def warm (requested : Option String) : IO String := do
  let config ← (← Config.load (← IO.currentDir)).mapM withDefaultMatcher
  let state ← diagnosticState
  let selected ← config.mapM fun config =>
    IO.ofExcept (Config.resolve config (state.map (·.profile) |>.getD config.defaultProfile))
  let eggs ← match requested with
    | some raw =>
        let named := config.bind (fun config => config.eggs.find? (·.name == raw))
        pure [named.getD {name := raw, path := .mk raw}]
    | none =>
        let some selection := selected | throw (IO.userError "specify a DB path: egg warm PATH")
        pure selection.read
  let command ← match config with
    | some config => pure config.semanticMatcher
    | none => MiniLM.command (← Paths.installRoot)
  let command := command.getD [(← IO.appPath).toString,"search-provider","--mode","lexical"]
  let sourceGroups ← eggs.mapM cacheSources
  let results ← (eggs.zip sourceGroups).mapM fun (egg,sources) => do
    let writable := selected.all fun selection =>
      selection.write.any (fun target => target.path.normalize == egg.path.normalize)
    let results ← sources.mapM fun source => Warm.run source command writable
    return Json.mkObj [("name",toJson egg.name),("path",toJson egg.path.toString),("sources",toJson results)]
  let current ← (sourceGroups.toArray.flatMap id).mapM fun source => do
    let current ← DB.PageMap.pin source.directory
    unless current.head.identity == source.head.identity do throw (IO.userError "warm source incarnation changed")
    return current
  let owners ← OwnerViews.prepare current
  pure (Json.mkObj [("databases", toJson results),("ownerView",toJson owners)]).compress

def controlSession : IO String := do
  match ← IO.getEnv "CODEX_THREAD_ID" with
  | some session => pure session
  | none => throw (IO.userError "run egg through Codex ! shell UI")

def currentConfig : IO Config.Config := do
  let cwd ← IO.currentDir
  let some config ← Config.load cwd |
    throw (IO.userError "no .eggshell.toml or global Eggshell config")
  pure config

def currentSelection (config : Config.Config) (state : ThreadState) : IO Config.Selection :=
  match Config.resolve config state.profile with
  | .ok selection => pure selection
  | .error message => throw (IO.userError message)

def statusLine (selection : Config.Selection) (state : ThreadState)
    (pending : Option PendingTurn) : String :=
  let enabled := if state.enabled then "on" else "off"
  let reads := " ".intercalate (selection.read.map (·.name))
  let write := selection.write.map (·.name) |>.getD "read-only"
  let pendingText := match pending with
    | none => "none"
    | some pending =>
        let phase := if pending.closed || pending.finalMessage.isSome then "sealed" else "active"
        s!"{phase}:{pending.turnId.take 8}"
  s!"egg {enabled} {state.profile} [{reads}] → {write} pending:{pendingText}"

def chooseTarget (pending : PendingTurn) : IO System.FilePath := do
  match pending.write with
  | some path => pure (System.FilePath.mk path)
  | none => throw (IO.userError "this turn was recorded without a save target")

def graphForSelection (selection : Config.Selection) : IO Persistence.Composite := do
  let sources ← selection.read.toArray.mapM cacheSources
  let graphs ← (sources.flatMap id).mapM Persistence.Store.materialize
  pure {
    values := graphs.toList.flatMap (·.values) |>.eraseDups
    unions := graphs.toList.flatMap fun graph => graph.unions.map (·.edge)
    authorities := graphs.toList.map (·.authority)
    origins := graphs.toList.flatMap fun graph => graph.values.map (·,graph.authority)
    unionOrigins := graphs.toList.flatMap fun graph => graph.unions.map (·.edge,graph.authority)
  }

def renderFind (composite : Persistence.Composite) (query : String) : String :=
  let needle := query.toLower
  let found := allNodes composite |>.filterMap fun value => do
    let text ← Matcher.atomText? value
    if text.toLower.contains needle then
      some s!"{valueKey value}  {shortValue value 500}"
    else none
  if found.isEmpty then "no matching Atom" else "\n".intercalate found

def unionKey (edge : UnionEdge) : String :=
  Persistence.Store.unionDisplayKey edge.left edge.right

def renderClass (composite : Persistence.Composite) (value : Value) : IO String := do
  match QuotientBuilder.build? (allNodes composite) composite.unions [] with
  | none => throw (IO.userError "stored Union classes failed certification")
  | some quotient =>
      let representative := quotient.canonical value
      let members := allNodes composite |>.filter fun member =>
        quotient.toEquality.same member value
      let unions := composite.unionOrigins.filterMap fun (edge, authority) =>
        if quotient.toEquality.same edge.left value ||
            quotient.toEquality.same edge.right value then
          some (s!"UNION {unionKey edge} {valueKey edge.left} = " ++
            s!"{valueKey edge.right} authority={valueKey authority}")
        else none
      let unionText := if unions.isEmpty then "" else
        "\n" ++ "\n".intercalate unions
      pure <| "CLASS representative=" ++ valueKey representative ++ "\n" ++
        "\n".intercalate (members.map fun member =>
          s!"{valueKey member}  {shortValue member 1000}") ++ unionText

def graphClosure (root : Value) : List Value := root.nodes.eraseDups

def renderRoots (roots : List Value) : String :=
  "\n".intercalate <| roots.flatMap graphClosure |>.eraseDups |>.map (fun value =>
    s!"{valueKey value}  {shortValue value 4000}")

def persistUnion (target : System.FilePath) (left right : Value) : IO UnionEdge := do
  if safe : Value.sameExactFootprint left right then
    let snapshot ← DB.PageMap.pin target
    let edge : UnionEdge := {
        left
        right
        scope := .workspace (← Persistence.Store.authority snapshot)
        exactAuthority := Value.sameExactFootprint_sound safe
      }
    if left == right then return edge
    let _ ← DB.PageMap.withWriter snapshot fun writer => do
      let intern : Persistence.Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let leftId ← intern.value left
      let rightId ← intern.value right
      if (← writer.get (Persistence.Store.unionPairKey leftId rightId)).isSome then return
      Persistence.Store.addUnions intern [edge]
      Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := true}
    pure edge
  else throw (IO.userError "Union would change Exact authority")

def splitPersistentUnion (target : System.FilePath) (key : String) : IO UnionEdge :=
  Persistence.withLock target do
    let snapshot ← DB.PageMap.pin target
    let some entry ← Persistence.Store.locateUnion? snapshot key |
      throw (IO.userError s!"Union {key} is not owned by {target}")
    let _ ← DB.PageMap.withWriter snapshot fun writer => do
      Persistence.Store.removeUnion writer entry
      Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := true}
    pure entry.edge

/-- Validate syntax before touching project or session state. The first flag
selects a read-only path; debug operations retain their original kernel rules. -/
def controlRequest : List String → Except String (Bool × List String)
  | [] => .ok (true,[])
  | ["inspect"] => .ok (true,["inspect"])
  | ["graph"] => .ok (true,["graph"])
  | ["why"] => .ok (true,["why"])
  | ["diff"] => .ok (true,["diff"])
  | ["on"] => .ok (false,["on"])
  | ["off"] => .ok (false,["off"])
  | ["drop"] => .ok (false,["drop"])
  | ["keep"] => .ok (false,["keep"])
  | ["use",profile] => .ok (false,["use",profile])
  | ["next",profile] => .ok (false,["next",profile])
  | ["debug","class",key] => .ok (true,["class",key])
  | ["debug","union",left,right] => .ok (false,["union",left,right])
  | ["debug","split",key] => .ok (false,["split",key])
  | "debug" :: "graph" :: (root :: roots) => .ok (true,"graph" :: root :: roots)
  | "debug" :: "find" :: (word :: words) => .ok (true,"find" :: word :: words)
  | "debug" :: "next-graph" :: (root :: roots) => .ok (false,"next" :: "graph" :: root :: roots)
  | _ => .error controlUsage

/-- Read the atomically published state without acquiring the writer's lock
or quarantining malformed files. These observations never authorize reuse or
publication. A missing chat uses the current project's configured profile. -/
def readControl (arguments : List String) : IO String := do
  let config ← currentConfig
  let files ← (← IO.getEnv "CODEX_THREAD_ID").mapM sessionFiles
  let stored ← files.mapM fun paths => readJson? (α := ThreadState) paths.state stateJsonDefaults
  let state := (stored.getD none).getD (defaultState config)
  let pending ← if arguments == ["graph"] || arguments == ["why"] then pure none
    else do
      let staged ← files.mapM fun paths => readJson? (α := PendingTurn) paths.pending pendingJsonDefaults
      pure (staged.getD none)
  let selection ← currentSelection config state
  match arguments with
  | [] => pure (statusLine selection state pending)
  | ["inspect"] => do
      let reads := ", ".intercalate (selection.read.map fun egg => s!"{egg.name}={egg.path}")
      let heads ← selection.read.mapM fun egg => do
        let snapshots ← cacheSources egg
        if snapshots.isEmpty then pure s!"{egg.name}:missing" else
          pure (egg.name ++ ":" ++ ";".intercalate (snapshots.toList.map fun snapshot =>
            s!"{snapshot.head.identity}:revision={snapshot.head.revision},rows={snapshot.head.root.map (·.rows) |>.getD 0}"))
      pure (statusLine selection state pending ++ s!"\nread=[{reads}]\n" ++
        "heads=[" ++ "; ".intercalate heads ++ s!"]\nconfig={config.source}")
  | ["graph"] => pure <| if !state.enabled then "egg off; no graph was sent"
      else if state.lastHandoff == "" then "no graph was sent" else state.lastHandoff
  | ["why"] => pure <| if !state.enabled then "egg off; no graph selection has run"
      else if state.lastReason == "" then "no graph selection has run" else state.lastReason
  | "graph" :: roots => do
      let composite ← graphForSelection selection
      renderRoots <$> IO.ofExcept (roots.mapM (resolveKey composite))
  | "find" :: query => do
      let composite ← graphForSelection selection
      pure (renderFind composite (" ".intercalate query))
  | ["class",key] => do
      let composite ← graphForSelection selection
      let value ← IO.ofExcept (resolveKey composite key)
      renderClass composite value
  | ["diff"] => do
      let some pending := pending | pure "no staged turn"
      let pending ← match files with
        | some paths => loadToolReceipts paths pending
        | none => pure pending
      let some target := pending.write | pure "this turn is read-only; nothing will be saved"
      let target := System.FilePath.mk target
      let graph ← if ← (target/"project").pathExists then do
          let project ← ProjectStore.openProject target
          let slot := ProjectStore.routeSlot pending.sessionId project.manifest.owners.size
          Persistence.Store.header (← project.current slot)
        else match ← DB.PageMap.open? target with
          | some snapshot => Persistence.Store.header snapshot
          | none => pure (Graph.empty (← Persistence.freshAuthority))
      let compiled ← IO.ofExcept (compile graph pending target.toString)
      pure s!"target={target}\nbase-revision={graph.revision}\nstaged-values={compiled.transaction.stagedValues.length}\noutcomes={compiled.promotion.outcomeRelations.length}"
  | _ => throw (IO.userError controlUsage)

def control (arguments : List String) : IO String := do
  let session ← controlSession
  withSession session fun files => do
    if arguments == ["off"] then
      let state := (← readState? files).getD { profile := "work" }
      quarantine files.pending
      writeJson files.state { state with
        enabled := false, epoch := state.epoch + 1, offers := [],
        nextProfile := none, nextProjection := none }
      return "egg off (memory disabled; no graph will be stored or sent)"
    let config ← currentConfig
    let mut state := (← readState? files).getD
      (defaultState config)
    if arguments == ["on"] &&
        state.lastReason.startsWith "memory disabled after invalid session state:" then
      state := { state with profile := config.defaultProfile }
    let pending ← readPending? files
    let selection ← currentSelection config state
    match arguments with
    | ["on"] =>
        state := { state with enabled := true }
        writeJson files.state state
        pure "egg on (memory enabled)"
    | ["use", profile] =>
        let _ ← match Config.resolve config profile with
          | .ok selection => pure selection
          | .error message => throw (IO.userError message)
        state := { state with profile }
        writeJson files.state state
        pure s!"egg {profile} selected"
    | ["next", profile] =>
        let _ ← match Config.resolve config profile with
          | .ok selection => pure selection
          | .error message => throw (IO.userError message)
        state := { state with nextProfile := some profile }
        writeJson files.state state
        pure s!"egg next {profile}"
    | ["next", "graph", "none"] =>
        state := { state with nextProjection := some .none }
        writeJson files.state state
        pure "egg next graph none"
    | ["next", "graph", "auto"] =>
        state := { state with nextProjection := some .automatic }
        writeJson files.state state
        pure "egg next graph auto"
    | "next" :: "graph" :: roots =>
        state := { state with nextProjection := some (.roots roots) }
        writeJson files.state state
        pure s!"egg next graph roots:{roots.length}"
    | ["drop"] =>
        removeIfExists files.pending
        pure "egg cleared the active turn; saved observations and queued commits are retained"
    | ["keep"] =>
        if !state.enabled then
          throw (IO.userError "Eggshell is off; run !egg on before keeping a turn")
        let some pending := pending |
          throw (IO.userError "no staged turn")
        if !pending.closed && pending.finalMessage.isNone then
          throw (IO.userError "active turn cannot be kept")
        let target ← chooseTarget pending
        let promotion ← promote pending target
        -- The foreground command publishes; its indexing runs in the same
        -- durable background lane as native terminal observations.
        queueCheckpoint files { pending with write := some target.toString }
        let _sourceReceipt := promotion.source
        removeIfExists files.pending
        pure s!"egg kept {pending.turnId.take 8} → {target}"
    | ["union", leftKey, rightKey] =>
        if !state.enabled then
          throw (IO.userError "Eggshell is off; run !egg on before changing a graph")
        let target ← match selection.write with
          | some egg => pure egg.path
          | none => throw (IO.userError "current profile is read-only")
        if ← (target/"project").pathExists then
          throw (IO.userError "manual Union requires an explicit physical-source debug configuration")
        let values ← readSelection selection [leftKey, rightKey]
        let [left, right] := values | throw (IO.userError "selected Union endpoint arity changed")
        let edge ← persistUnion target left right
        pure s!"egg union {unionKey edge} {leftKey} = {rightKey} → {target}"
    | ["split", key] =>
        if !state.enabled then
          throw (IO.userError "Eggshell is off; run !egg on before changing a graph")
        let target ← match selection.write with
          | some egg => pure egg.path
          | none => throw (IO.userError "current profile is read-only")
        if ← (target/"project").pathExists then
          throw (IO.userError "manual Union requires an explicit physical-source debug configuration")
        let edge ← splitPersistentUnion target key
        pure s!"egg split {key} {valueKey edge.left} != {valueKey edge.right} → {target}"
    | _ => throw (IO.userError controlUsage)

def eggControl (arguments : List String) : IO UInt32 := do
  if arguments = ["--help"] || arguments = ["-h"] then
    IO.println controlUsage
    return 0
  try
    let output ← match arguments with
      | ["doctor"] => doctor
      | ["warm"] => warm none
      | ["warm", requested] => warm (some requested)
      | _ => do
          let (readOnly,request) ← IO.ofExcept (controlRequest arguments)
          if readOnly then readControl request else control request
    IO.println output
    pure 0
  catch error =>
    IO.eprintln s!"egg: {error}"
    pure 1

end Eggshell.Plugin
