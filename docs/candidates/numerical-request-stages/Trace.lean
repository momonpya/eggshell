
/-- Owned by one keyed request. Only bounded stage labels and monotonic
timestamps survive a failure; no query, vector, path or response is retained. -/
structure StageTrace where
  events : List (String × Nat) := []
  omitted : Nat := 0

def StageTrace.advance (trace : StageTrace) (label : String) (now : Nat) : StageTrace :=
  {events := (((label.take 160).copy,now)::trace.events).take 32
   omitted := trace.omitted + if trace.events.length < 32 then 0 else 1}

theorem StageTrace.advance_bounded (trace : StageTrace) (label : String) (now : Nat) :
    (trace.advance label now).events.length ≤ 32 := by
  simp only [advance,List.length_take,List.length_cons]
  omega

theorem StageTrace.advance_current (trace : StageTrace) (label : String) (now : Nat) :
    (trace.advance label now).events.head? = some ((label.take 160).copy,now) := by
  simp [advance]
