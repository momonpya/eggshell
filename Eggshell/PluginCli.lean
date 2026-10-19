module

public import Eggshell.PluginHooks
public import Eggshell.Warm

@[expose] public section

namespace Eggshell.Plugin
open Lean

def controlUsage : String :=
  "usage: egg [init|on|off|use P|next P|next graph auto|none|VALUES|keep [EGG]|drop|" ++
  "graph [VALUES]|why|find TEXT|class VALUE|union LEFT RIGHT|split UNION|" ++
  "diff [EGG]|inspect|doctor|warm [EGG|PATH]]"

def diagnosticState : IO (Option ThreadState) := do
  match ← IO.getEnv "CODEX_THREAD_ID" with
  | none => pure none
  | some id => readJson? (← sessionFiles id).state stateJsonDefaults

def databaseCacheStatus (egg : Config.Egg) (command : Option (List String)) : IO Json := do
  let fields := [("name", toJson egg.name), ("path", toJson egg.path.toString)]
  try
    let some snapshot ← DB.PageMap.open? egg.path |
      return Json.mkObj (fields ++ [("state", toJson "absent")])
    let some command := command |
      return Json.mkObj (fields ++ [("state", toJson "provider-unavailable")])
    let options ← Warm.options snapshot command
    let inspected ← Warm.inspect snapshot options
    let state := if inspected.coverage.invalid > 0 then "invalid"
      else if inspected.coverage.missing > 0 then "cold" else "warm"
    pure (Json.mkObj (fields ++ [("state", toJson state), ("coverage", toJson inspected.coverage)]))
  catch error => pure (Json.mkObj (fields ++ [("state", toJson "error"), ("reason", toJson error.toString)]))

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
  let some command := command |
    throw (IO.userError "numerical provider is disabled or not installed")
  let results ← eggs.mapM fun egg => do
    let writable := selected.all fun selection =>
      selection.write.any (fun target => target.path.normalize == egg.path.normalize)
    Warm.run (← DB.PageMap.pin egg.path) command writable
  pure (Json.mkObj [("databases", toJson results)]).compress

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

def chooseTarget (config : Config.Config) (pending : PendingTurn)
    (requested : Option String) : IO System.FilePath := do
  match requested with
  | some name =>
      match config.eggs.find? (·.name == name) with
      | some egg => pure egg.path
      | none => throw (IO.userError s!"unknown egg {name}")
  | none =>
      match pending.write with
      | some path => pure (System.FilePath.mk path)
      | none => throw (IO.userError "pending turn has no write target; name one with !egg keep EGG")

def graphForSelection (selection : Config.Selection) : IO Persistence.Composite :=
  Persistence.loadComposite (selection.read.map (·.path))

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
      Persistence.Store.writeChange writer ⟨[], [], true⟩
    pure edge
  else throw (IO.userError "Union would change Exact authority")

def splitPersistentUnion (target : System.FilePath) (key : String) : IO UnionEdge :=
  Persistence.withLock target do
    let snapshot ← DB.PageMap.pin target
    let some entry ← Persistence.Store.locateUnion? snapshot key |
      throw (IO.userError s!"Union {key} is not owned by {target}")
    let _ ← DB.PageMap.withWriter snapshot fun writer => do
      Persistence.Store.removeUnion writer entry
      Persistence.Store.writeChange writer ⟨[], [], true⟩
    pure entry.edge

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
    | [] => pure (statusLine selection state pending)
    | ["--help"] | ["-h"] => pure controlUsage
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
    | ["keep"] | ["keep", _] =>
        if !state.enabled then
          throw (IO.userError "Eggshell is off; run !egg on before keeping a turn")
        let some pending := pending |
          throw (IO.userError "no staged turn")
        if !pending.closed && pending.finalMessage.isNone then
          throw (IO.userError "active turn cannot be kept")
        let requested := arguments.drop 1 |>.head?
        let target ← chooseTarget config pending requested
        let promotion ← promote pending target
        -- The foreground command publishes; its indexing runs in the same
        -- durable background lane as native terminal observations.
        queueCheckpoint files { pending with write := some target.toString }
        state := addDeliveredGraphs state
          (promotion.outcomeRelations.map nativeHistoryKey)
        writeJson files.state state
        removeIfExists files.pending
        pure s!"egg kept {pending.turnId.take 8} → {target}"
    | ["graph"] =>
        pure <| if !state.enabled then "egg off; no graph was sent"
          else if state.lastHandoff = "" then "no graph was sent" else state.lastHandoff
    | ["why"] =>
        pure <| if !state.enabled then "egg off; no graph selection has run"
          else if state.lastReason = "" then "no graph selection has run" else state.lastReason
    | "graph" :: roots =>
        let values ← readSelection selection roots
        pure (renderRoots values)
    | "find" :: query =>
        let composite ← graphForSelection selection
        pure (renderFind composite (" ".intercalate query))
    | ["class", key] =>
        let composite ← graphForSelection selection
        let value ← match resolveKey composite key with
          | .ok value => pure value
          | .error message => throw (IO.userError message)
        renderClass composite value
    | ["union", leftKey, rightKey] =>
        if !state.enabled then
          throw (IO.userError "Eggshell is off; run !egg on before changing a graph")
        let target ← match selection.write with
          | some egg => pure egg.path
          | none => throw (IO.userError "current profile is read-only")
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
        let edge ← splitPersistentUnion target key
        pure s!"egg split {key} {valueKey edge.left} != {valueKey edge.right} → {target}"
    | ["inspect"] =>
        let reads := ", ".intercalate (selection.read.map fun egg =>
          s!"{egg.name}={egg.path}")
        let heads ← selection.read.mapM fun egg => do
          match ← DB.PageMap.open? egg.path with
          | none => pure s!"{egg.name}:missing"
          | some snapshot => pure (s!"{egg.name}:revision={snapshot.head.revision}," ++
              s!"values={(← Persistence.Store.rootIds snapshot).length}," ++
              s!"unions={(← Persistence.Store.unionPairs snapshot).length}")
        pure (statusLine selection state pending ++ s!"\nread=[{reads}]\n" ++
          "heads=[" ++ "; ".intercalate heads ++ s!"]\nconfig={config.source}")
    | ["diff"] | ["diff", _] =>
        let some pending := pending |
          throw (IO.userError "no staged turn")
        let requested := arguments.drop 1 |>.head?
        let target ← chooseTarget config pending requested
        let graph ← match ← DB.PageMap.open? target with
          | some snapshot => Persistence.Store.header snapshot
          | none => pure (Graph.empty (← Persistence.freshAuthority))
        let compiled ← match compile graph pending target.toString with
          | .ok compiled => pure compiled
          | .error message => throw (IO.userError message)
        pure s!"target={target}\nbase-revision={graph.revision}\nstaged-values={compiled.transaction.stagedValues.length}\noutcomes={compiled.promotion.outcomeRelations.length}"
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
      | _ => control arguments
    IO.println output
    pure 0
  catch error =>
    IO.eprintln s!"egg: {error}"
    pure 1

end Eggshell.Plugin
