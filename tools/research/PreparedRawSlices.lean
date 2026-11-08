module
public import Eggshell.Handoff
@[expose] public section

namespace Eggshell.Research.PreparedRawSlices
open Plugin

/-- A raw slice's exact metadata, without constructing a body which a prepared
source shell will replace. There is no IO, cache, lock or certification here. -/
def metadata (whole : Bool) : (String × List Selected) → Option TransportSlice
  | (_,[]) => none
  | (_,first :: rest) => some {
      owner := some first.matched.edge.relation
      keys := ((if whole then ["g:" ++ ownerKey first ++ ":" ++ relationKey first.matched.edge.outcome] else []) ++
        (first :: rest).map graphKey) |>.eraseDups
      text := ""
      members := first :: rest
      visibleKeys := (first :: rest).map graphKey |>.eraseDups }

def clearText (slice : TransportSlice) : TransportSlice := {slice with text := ""}

theorem metadata_exact (staged : List Value) (whole : Bool) (group : String × List Selected) :
    metadata whole group = (rawSlice staged whole group).map clearText := by
  rcases group with ⟨key,members⟩
  cases members <;> rfl

def shell (prepared : Synapses.PreparedPlanMetadata.Shell) (slice : TransportSlice) : TransportSlice :=
  {slice with keys := [],text := "",context := none,shared := none,shell := some prepared}

theorem shell_clearText (prepared : Synapses.PreparedPlanMetadata.Shell) (slice : TransportSlice) :
    shell prepared (clearText slice) = shell prepared slice := rfl

/-- Arbitrary work, observations, match authority, provenance and staged state.
Only the text already discarded by the shell projection is omitted. -/
theorem shell_metadata_exact (prepared : Synapses.PreparedPlanMetadata.Shell)
    (staged : List Value) (whole : Bool) (group : String × List Selected) :
    (metadata whole group).map (shell prepared) =
      (rawSlice staged whole group).map (shell prepared) := by
  rw [metadata_exact]
  simp only [Option.map_map]
  rfl

theorem metadata_presence (staged : List Value) (whole : Bool) (group : String × List Selected) :
    (metadata whole group).isSome = (rawSlice staged whole group).isSome := by
  rw [metadata_exact]
  cases rawSlice staged whole group <;> rfl

theorem metadata_has_members (whole : Bool) (group : String × List Selected) :
    (metadata whole group).map (·.members) = (rawSlice [] whole group).map (·.members) := by
  rw [metadata_exact []]
  simp only [Option.map_map]
  rfl

end Eggshell.Research.PreparedRawSlices
