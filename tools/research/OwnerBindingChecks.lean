import Main
open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.OwnerBindingChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def preparedOriginals (view : OwnerViews.Reader) (id : Nat) : IO (List PreparedOwners.Original) := do
  return (← Plugin.preparedOwnerBinding view id).originals
def coordinates (originals : List PreparedOwners.Original) : List (Nat × Nat × Nat) :=
  originals.map fun original => (original.source,original.ordinal,original.node)
def reference (sources : Array PageMap.Snapshot) (value : Value) : IO (List (Nat × Nat × Nat)) := do
  let mut found := []
  for source in List.finRange sources.size do
    if let some (ordinal,node) ← liveRoot? sources[source] value then found := found++[(source.val,ordinal,node)]
  return found
def audit (view : OwnerViews.Reader) : IO Json := do
  let ids ← match view.base.allOwners with
    | none => pure []
    | some root => view.base.bitmap.members root.height root
  let sources := view.base.inputs.map (·.original)
  check (!ids.isEmpty && ids.length == view.base.counts.1) "owner audit lost its complete nonempty domain"
  let readers ← NodeReaders.new sources
  let some firstId := ids.head? | throw (IO.userError "missing audit owner")
  let binding ← Plugin.preparedOwnerBinding view firstId
  let some original := binding.originals.head? | throw (IO.userError "missing audit original")
  let some input := view.base.inputs[original.source]? | throw (IO.userError "missing audit source")
  let bad ← [
    ("foreign-source",{original with source := sources.size}),
    ("wrong-ordinal",{original with ordinal := ← getNat input.original.get "roots"}),
    ("missing-member",{original with node := ← getNat input.original.get "nodes"})].toArray.mapM fun (name,wrong) => do
      let refused ← try Plugin.checkPreparedOriginals sources [wrong]; pure false catch _ => pure true
      check refused ("invalid prepared original accepted: "++name)
      return (name,refused)
  let values ← ids.mapM fun id => do
    let entry ← OwnerViews.entry view id
    let some original := entry.originals.head? | throw (IO.userError "prepared owner has no original")
    if bounded : original.source < sources.size then
      return (id,← (readers.at ⟨original.source,bounded⟩).read original.node)
    else throw (IO.userError "prepared owner lost its original source")
  let mut checks := 0
  for (id,value) in values do
    let actual ← preparedOriginals view id
    check (toJson (coordinates actual) == toJson (← reference sources value)) "prepared source positions differ from complete structural lookup"
    checks := checks+1
  let mut timings := #[]
  for pair in [0,1,2] do
    for fast in (if pair == 1 then [true,false] else [false,true]) do
      let started ← IO.monoNanosNow
      let mut positions := 0
      for (id,value) in values do
        let found ← if fast then coordinates <$> preparedOriginals view id else reference sources value
        positions := positions+found.length
      timings := timings.push (Json.mkObj [("pair",toJson pair),("prepared",toJson fast),
        ("nanos",toJson ((← IO.monoNanosNow)-started)),("positions",toJson positions)])
  return Json.mkObj [("owners",toJson ids.length),("checked",toJson checks),
    ("structuralSourceProbesPerRound",toJson (ids.length*sources.size)),("negativeCoordinates",toJson bad),("timings",toJson timings)]
def auditCaptured (root : System.FilePath) : IO Unit := do
  let (mixed,latest) ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured.json")) >>=
    fromJson? (α := Array SourceOwners.Captured × Array SourceOwners.Captured))
  let mut reports := #[]
  for captured in [mixed,latest] do
    let some base ← SourceOwners.open? captured "project/authorized-scope" | throw (IO.userError "retained source cut unavailable")
    let mut stride := 1
    for input in base.inputs do stride := max stride ((← getNat input.original.get "roots")+1)
    reports := reports.push (← audit ⟨base,stride⟩)
  IO.FS.writeFile (root/"owner-bindings.json") ((toJson reports).pretty++"\n")
  IO.println (toJson reports).compress
def run (source root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier owner binding audit"
  IO.FS.createDirAll root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identity.exitCode == 0) "audit runtime identity missing"
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let project := (source/"work.project").toString
  let config := root/"eggshell.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = false\n[eggs]\nwork = \""++project++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let warm ← IO.Process.output {
    cmd := (← IO.appPath).toString
    args := #["egg","warm",project]
    env := #[("EGGSHELL_CONFIG",some config.toString)]}
  IO.FS.writeFile (root/"warm-stdout.json") warm.stdout
  IO.FS.writeFile (root/"warm-stderr.txt") warm.stderr
  check (warm.exitCode == 0) "owner binding audit warm failed"
  let sources ← (List.range 16).toArray.mapM fun owner => PageMap.pin (source/"work.project/owners"/toString owner/"source.egg")
  let expected := (← read (source/"frozen-readback.json")).getObjValD "sourceHeads"
  check (toJson (sources.map (·.head)) == expected) "frozen original cut changed"
  try
    let view ← OwnerViews.restore (← OwnerViews.prepare sources) sources
    let report ← audit view
    let current ← sources.mapM fun original => PageMap.pin original.directory
    check (toJson (current.map (·.head)) == expected) "read-only owner audit changed originals"
    IO.FS.writeFile (root/"report.json") ((report.setObjVal! "sourceHeadsUnchanged" (toJson true)).pretty++"\n")
    IO.println report.compress
  finally
    let _ ← Publication.Client.control "shutdown"
    pure ()
end Eggshell.Research.OwnerBindingChecks
