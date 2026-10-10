module

public import Eggshell.GraphStore

@[expose] public section
namespace Eggshell.Persistence
open Lean

/-- Normal storage is the page DB. Whole-graph materialization is an explicit
inspection path; promotion and indexing use selective snapshots below. -/
def loadExisting? (path : System.FilePath) : IO (Option Graph) := do
  match ← DB.PageMap.open? path with
  | none => pure none
  | some snapshot => some <$> Store.materialize snapshot

def load (path : System.FilePath) : IO Graph := do
  let some graph ← loadExisting? path | throw (IO.userError "memory DB does not exist")
  pure graph

def freshAuthority : IO Value := do
  pure (.text ("egg authority " ++ Blake3.hex (← IO.getRandomBytes 32)))

def ensureSnapshot (path : System.FilePath) : IO Store.Snapshot := do
  match ← DB.PageMap.open? path with
  | some snapshot => pure snapshot
  | none =>
      let authority ← freshAuthority
      DB.PageMap.create path (valueToJson authority).compress

/-- Explicit graph import/administrative replacement. Payload and indexes are
published under one root. Ordinary hooks do not call a full-graph save. -/
def saveAtomic (path : System.FilePath) (graph : Graph) : IO Unit := do
  let snapshot ← match ← DB.PageMap.open? path with
    | some snapshot => pure snapshot
    | none => DB.PageMap.create path (valueToJson graph.authority).compress
  unless (← Store.authority snapshot) == graph.authority do
    throw (IO.userError "graph belongs to another authority")
  let _ ← DB.PageMap.withWriter snapshot fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let previous ← Store.rootIds snapshot
    let desired ← graph.values.mapM intern.value
    let removed := previous.filter (!desired.contains ·)
    let added := desired.filter (!previous.contains ·)
    -- Keep one stable authoritative insertion order. A caller asking for a
    -- different tie order is rejected rather than silently changing it.
    unless desired == previous.filter desired.contains ++ added do
      throw (IO.userError "administrative replacement changed the retained root order")
    for id in removed do Store.removeRoot writer id
    for value in graph.values do let _ ← intern.root value; pure ()
    let oldPairs ← Store.unionPairs snapshot
    let newPairs ← graph.unions.mapM fun edge => do
      pure (← intern.value edge.edge.left, ← intern.value edge.edge.right)
    let unionsChanged := oldPairs != newPairs
    if unionsChanged then
      for (ordinal, (left, right)) in (← Store.unionDirectory snapshot) do
        writer.put (Store.unionPairKey left right) none
        writer.put (Store.key "union" ordinal) none
      for (left, right) in oldPairs do
        let left ← Store.readNode snapshot snapshot.get left
        let right ← Store.readNode snapshot snapshot.get right
        writer.put ("unionKey:" ++ Store.unionDisplayKey left right) none
      Store.putNat writer "unions" 0
      Store.addUnions intern (graph.unions.map (·.edge))
    if !added.isEmpty || !removed.isEmpty || unionsChanged then
      Store.writeChange writer ⟨added, removed, unionsChanged⟩
  pure ()

def lockPath (path : System.FilePath) : System.FilePath :=
  .mk (path.toString ++ ".guard")

def acquireLock (handle : IO.FS.Handle) (path : System.FilePath) : Nat → IO Unit
  | 0 => throw (IO.userError s!"timed out waiting for {lockPath path}")
  | retries + 1 =>
      do
        if ← handle.tryLock then return
        IO.sleep 5
        acquireLock handle path retries

def withLockWithin (path : System.FilePath) (waitMs : Nat) (action : IO α) : IO α := do
  rejectSymlinkAncestors path
  -- A kernel-owned lock is released even if its owner is killed. Never unlink
  -- this file: doing so would create two independent lock inodes.
  let guard := lockPath path
  rejectSymlinkAncestors guard
  if let some parent := guard.parent then
    if !(← parent.pathExists) then privateDirectory parent
  let handle ← IO.FS.Handle.mk guard .append
  privateFile guard
  acquireLock handle path (waitMs / 5 + 1)
  try
    action
  finally
    handle.unlock

def withLock (path : System.FilePath) (action : IO α) : IO α :=
  withLockWithin path 1000 action

def create (path : System.FilePath) : IO Graph :=
  withLock path do
    if (← FileSystem.symlinkMetadata? path).isSome then
      throw (IO.userError "memory DB already exists")
    Store.header (← ensureSnapshot path)

/-- The turn compiler receives only the current authority/revision. Existing
root membership and frequency updates are resolved by point lookup, rather
than loading the old graph to filter a newly compiled turn. The returned view
contains the submitted, now-published roots; it is not the entire database. -/
def appendPrepared (path : System.FilePath)
    (prepare : Graph → Except String (Transaction × α)) : IO (Graph × α) :=
  withLock path do
    let snapshot ← ensureSnapshot path
    let header ← Store.header snapshot
    let (transaction, result) ← IO.ofExcept (prepare header)
    unless transaction.appliesTo header do throw (IO.userError "stale DB transaction")
    let (_, head, _) ← DB.PageMap.withWriter snapshot fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let mut added := []
      for value in transaction.stagedValues do
        let id ← intern.value value
        let fresh := (← writer.get (Store.key "member" id)).isNone
        let _ ← intern.root value
        if fresh then added := id :: added
      let oldUnions ← Store.getNat writer.get "unions"
      Store.addUnions intern (transaction.stagedUnions.map (·.edge))
      let unionsChanged := (← Store.getNat writer.get "unions") != oldUnions
      if !added.isEmpty || unionsChanged then Store.writeChange writer ⟨added.reverse, [], unionsChanged⟩
    let values := transaction.stagedValues
    let publication : Graph := {
      authority := header.authority
      revision := head.revision
      values := values
      unions := []
      values_wellFormed := transaction.stagedValues_wellFormed }
    pure (publication, result)

structure Composite where
  values : List Value
  unions : List UnionEdge
  authorities : List Value
  origins : List (Value × Value)
  unionOrigins : List (UnionEdge × Value)
  deriving DecidableEq

def Composite.authoritiesFor (composite : Composite) (value : Value) : List Value :=
  (composite.origins.filterMap fun (candidate, authority) =>
    if candidate = value then some authority else none
  ).eraseDups

def loadComposite (paths : List System.FilePath) : IO Composite := do
  let graphs := (← paths.mapM loadExisting?).filterMap id
  pure {
    values := graphs.flatMap (·.values) |>.eraseDups
    unions := graphs.flatMap fun graph => graph.unions.map (·.edge)
    authorities := graphs.map (·.authority)
    origins := graphs.flatMap fun graph => graph.values.map (fun value =>
      (value, graph.authority))
    unionOrigins := graphs.flatMap fun graph => graph.unions.map (fun persistent =>
      (persistent.edge, graph.authority))
  }

/-- Deliberate fixture/exchange import, never an automatic read fallback. -/
def importGraphFile (source destination : System.FilePath) : IO Unit :=
  withLock destination do
    if (← FileSystem.symlinkMetadata? destination).isSome then
      throw (IO.userError "import destination already exists")
    let graph ← IO.ofExcept (decode (← IO.FS.readFile source))
    saveAtomic destination graph

end Eggshell.Persistence
