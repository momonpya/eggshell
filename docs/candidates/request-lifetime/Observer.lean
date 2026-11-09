import tools.research.ResourceGuard

namespace Eggshell.Research.RequestTimeline
open Lean

/-- Read-only OS observations. Full command arguments and request content
are not recorded; no signal, collector or cache intervention is exposed. -/
def observe (directory : String) (done : IO.Ref Bool) (path : System.FilePath) : IO Unit := do
  let observer := (← IO.Process.getPID).toNat
  let mut known : Std.HashMap Nat String := {}
  let handle ← IO.FS.Handle.mk path .write
  repeat
    let started ← IO.monoMsNow
    let record ← try
      let rows ← ResourceGuard.processes
      let excluded := ResourceGuard.ancestors rows observer
      let selected := ResourceGuard.owned rows excluded 0 known #[directory]
      let mut values := #[]
      for checked in selected do
        let row := checked.process
        known := known.insert row.pid row.identity
        values := values.push (Json.mkObj [("pid",toJson row.pid),("parent",toJson row.parent),
          ("rssKiB",toJson row.rssKiB),("program",toJson row.command[0]?),
          ("subcommand",toJson row.command[1]?)])
      if let some row := rows[observer]? then
        values := values.push (Json.mkObj [("pid",toJson row.pid),("parent",toJson row.parent),
          ("rssKiB",toJson row.rssKiB),("program",toJson row.command[0]?),
          ("subcommand",toJson "timeline-client")])
      pure (Json.mkObj [("atMs",toJson started),("rows",toJson values),
        ("elapsedMs",toJson ((← IO.monoMsNow)-started))])
    catch error => pure (Json.mkObj [("atMs",toJson started),("observationError",toJson error.toString)])
    handle.putStrLn record.compress
    handle.flush
    if ← done.get then break
    IO.sleep 200

def withObservation (directory : String) (path : System.FilePath) (action : IO α) : IO α := do
  unless path.isAbsolute && !(← path.pathExists) do throw (IO.userError "fresh timeline path required")
  let done ← IO.mkRef false
  let task ← IO.asTask (observe directory done path) .dedicated
  try action
  finally
    done.set true
    discard <| IO.ofExcept (← IO.wait task)

end Eggshell.Research.RequestTimeline
