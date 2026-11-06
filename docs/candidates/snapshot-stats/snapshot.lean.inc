/-- Only immutable scalar observations cross the publication-state lock. No
project queue, read handle, mutable reference or synchronization capability. -/
structure StatsSnapshot where
  projects : Nat
  queued : Nat
  active : Nat
  closed : Bool
  admittedBytes : Nat
  publishedGroups : Nat
  publishedReplies : Nat
  deriving BEq

def StatsSnapshot.capture (state : State) : StatsSnapshot :=
  ⟨state.projects.size,state.projects.foldl (fun count project => count+project.queue.size) 0,
    (state.projects.filter (·.active)).size,state.closed,state.admittedBytes,
    state.publishedGroups,state.publishedReplies⟩

def StatsSnapshot.fields (snapshot : StatsSnapshot) : List (String × Json) :=
  [("projects",toJson snapshot.projects),("queued",toJson snapshot.queued),
    ("active",toJson snapshot.active),("closed",toJson snapshot.closed),
    ("admittedBytes",toJson snapshot.admittedBytes),
    ("publishedGroups",toJson snapshot.publishedGroups),("publishedReplies",toJson snapshot.publishedReplies)]

theorem StatsSnapshot.original_fields (state : State) :
    (StatsSnapshot.capture state).fields =
    [("projects",toJson state.projects.size),
      ("queued",toJson (state.projects.foldl (fun count project => count+project.queue.size) 0)),
      ("active",toJson (state.projects.filter (·.active)).size),("closed",toJson state.closed),
      ("admittedBytes",toJson state.admittedBytes),
      ("publishedGroups",toJson state.publishedGroups),("publishedReplies",toJson state.publishedReplies)] := rfl

theorem StatsSnapshot.exact_counters (state : State) :
    (StatsSnapshot.capture state).closed = state.closed ∧
    (StatsSnapshot.capture state).admittedBytes = state.admittedBytes ∧
    (StatsSnapshot.capture state).publishedGroups = state.publishedGroups ∧
    (StatsSnapshot.capture state).publishedReplies = state.publishedReplies := ⟨rfl,rfl,rfl,rfl⟩
