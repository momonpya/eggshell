import Eggshell.PluginProjectContext
open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.PublicInputChecks
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def refused (action : IO α) : IO Bool := do try let _ ← action; return false catch _ => return true
def legacy (sources : Array PageMap.Snapshot) : IO (Array PreparedInputs.Reference × Option OwnerViews.Reference) := do
  let inputs ← sources.mapM fun source => do
    let mut found := none
    for storage in [Sidecar.Storage.database,.user] do
      let path ← PreparedInputs.folder source storage MiniLM.model SearchProvider.encoderContract
      if let some index ← PageMap.open? path then
        if let some bytes ← index.get (PreparedInputs.sourceKey source.head) then
          let input ← Synapses.Index.decode (α := PreparedInputs.Reference) bytes
          check (input.accepts source MiniLM.model SearchProvider.encoderContract) "legacy input changed source"
          found := some {input with usage := none}
          break
    let some selected := found | throw (IO.userError "independent legacy reference missing")
    return selected
  return (inputs,← OwnerViews.load? sources)
def projected (sources : Array PageMap.Snapshot) : IO (Array PreparedInputs.Reference × Option OwnerViews.Reference) := do
  let values ← sources.mapM fun source => do
    let some value ← PreparedInputs.public? source MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "prepared public projection missing")
    return value
  return (values.map (·.input),← PreparedInputs.publicOwners sources values)
def run (source root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier public input audit"
  IO.FS.createDirAll root
  let config := root/"eggshell.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = false\n[eggs]\nwork = \""++
    (source/"work.project").toString++"\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\n")
  let warm ← IO.Process.output {
    cmd := (← IO.appPath).toString
    args := #["egg","warm",(source/"work.project").toString],env := #[("EGGSHELL_CONFIG",some config.toString)]}
  IO.FS.writeFile (root/"warm.json") (Json.mkObj [("exitCode",toJson warm.exitCode.toNat),
    ("stdout",toJson warm.stdout),("stderr",toJson warm.stderr)]).pretty
  let stopped ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["publication-control","shutdown"]}
  check (warm.exitCode == 0 && stopped.exitCode == 0) "public publication warm failed"
  let project ← ProjectStore.openProject (source/"work.project")
  let expected ← IO.ofExcept (fromJson? ((← read (source/"frozen-readback.json")).getObjValD "sourceHeads") :
    Except String (Array PageMap.Head))
  let cut : ProjectStore.Cut := ⟨project.manifest.identity,expected⟩
  let view ← ProjectStore.openView project cut
  let baseline ← legacy view.sources
  let compiled ← projected view.sources
  check (toJson baseline == toJson compiled) "public projection differs from independent B-tree and owner lookup"
  let values ← view.sources.mapM fun original => do
    let some value ← PreparedInputs.public? original MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "public projection disappeared")
    return value
  check (← refused (PreparedInputs.publicOwners view.sources.pop values)) "partial inventory accepted"
  check (← refused (PreparedInputs.publicOwners view.sources values.reverse)) "reordered owner descriptors accepted"
  let some original := view.sources[0]? | throw (IO.userError "no original in audit")
  let some value := values[0]? | throw (IO.userError "no published input in audit")
  check value.input.numeric.isSome "same-original readiness test requires an existing numerical pair"
  for changed in [
      {value with directory := "/foreign/project"},
      {value with input := {value.input with usage := some original.head}},
      {value with input := {value.input with model := "foreign-model"}},
      {value with input := {value.input with source := {value.input.source with identity := "foreign"}}},
      {value with owner := value.owner.map fun item =>
        {item with captured := {item.captured with state := {item.captured.state with
          source := {item.captured.state.source with head := {original.head with bytes := original.head.bytes+1}}}}}}] do
    check (!(← changed.validFor original MiniLM.model SearchProvider.encoderContract)) "foreign/private public metadata accepted"
  -- Advance the actual atomically read record with the original head fixed.
  -- Restore it in finally; this is a publication-reader test, not a model run.
  let path ← PreparedInputs.folder original value.storage MiniLM.model SearchProvider.encoderContract
  let exact := PreparedInputs.publicPath path original.head
  let raw ← FileSystem.boundedBytes exact 131072
  try
    let lexical := {value with input := {value.input with numeric := none}}
    FileSystem.atomicExistingBytes exact (toJson lexical).compress.toUTF8
    let some before ← PreparedInputs.public? original MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "lexical-only publication disappeared")
    check before.input.numeric.isNone "old numeric root hid same-original readiness change"
    FileSystem.atomicExistingBytes exact raw
    let some after ← PreparedInputs.public? original MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "ready public publication disappeared")
    check (toJson after == toJson value && before.input.numeric.isNone) "advanced publication changed an older captured value"
  finally FileSystem.atomicExistingBytes exact raw
  let mut timings := #[]
  for pair in [:3] do
    for resident in (if pair == 1 then [true,false] else [false,true]) do
      let fresh ← ProjectStore.openView project cut
      let began ← IO.monoNanosNow
      let actual ← if resident then projected fresh.sources else legacy fresh.sources
      let elapsed := (← IO.monoNanosNow)-began
      check (toJson actual == toJson baseline) "alternating public capture changed complete frame"
      timings := timings.push (Json.mkObj [("pair",toJson pair),("projected",toJson resident),("elapsedNs",toJson elapsed)])
  let boundary ← PreparedInputs.boundary (view.sources.toList.map some) MiniLM.model SearchProvider.encoderContract
  let attached ← IO.ofExcept (PreparedInputs.attachBoundary boundary compiled.1)
  let frame : PreparedInputs.Frame := ⟨PreparedInputs.implementation,boundary.originals,attached,compiled.2⟩
  check (PreparedInputs.acceptsBoundary boundary frame) "compiled public inputs changed private/original boundary"
  let changed := {boundary with usage := boundary.usage.map fun _ => some original.head}
  let other ← IO.ofExcept (PreparedInputs.attachBoundary changed compiled.1)
  let privateFrame : PreparedInputs.Frame := ⟨PreparedInputs.implementation,changed.originals,other,compiled.2⟩
  check (PreparedInputs.acceptsBoundary changed privateFrame && !PreparedInputs.acceptsBoundary boundary privateFrame)
    "public publication mixed private usage between requesters"
  let overlay ← ProjectStore.create (root/"overlay.project") 2
  let first ← overlay.current 0
  let _ ← OwnerViews.prepareSource first .database
  let setReadOnly ← IO.Process.output {cmd := "/bin/chmod",args := #["-R","a-w",overlay.directory.toString]}
  check (setReadOnly.exitCode == 0) "cannot create read-only original fixture"
  try
    let _ ← PreparedInputs.publish first .user MiniLM.model SearchProvider.encoderContract false
    let some privateOverlay ← PreparedInputs.public? first MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "read-only original publication was unavailable")
    check (privateOverlay.storage == .user && privateOverlay.owner.any (·.storage == .database))
      "public overlay forced independent owner roots into its own storage location"
  finally
    let writable ← IO.Process.output {cmd := "/bin/chmod",args := #["-R","u+w",overlay.directory.toString]}
    check (writable.exitCode == 0) "cannot restore read-only fixture permissions"
  let other ← overlay.current 1
  let mixed := view.sources++#[first,other]
  let mixedSnapshots := mixed.toList.map some
  let mixedBoundary ← PreparedInputs.boundary mixedSnapshots MiniLM.model SearchProvider.encoderContract
  let pending : PendingTurn := {
    sessionId := "public-capture-audit",turnId := "turn",cwd := root.toString,prompt := "unrelated"
    profile := "work",semanticMatcher := none,read := [],write := none,handoffChars := 120000,projection := .automatic}
  check ((← ProjectContext.captureInputs pending mixedSnapshots (some mixedBoundary) false).isNone)
    "a ready subset replaced a mixed project boundary"
  let _ ← OwnerViews.prepareSource other .user
  let _ ← PreparedInputs.publish other .user MiniLM.model SearchProvider.encoderContract false
  let some complete ← ProjectContext.captureInputs pending mixedSnapshots (some mixedBoundary) false |
    throw (IO.userError "complete mixed project capture remained missing")
  let completeFrame ← IO.ofExcept (fromJson? complete.payload : Except String PreparedInputs.Frame)
  check (PreparedInputs.acceptsBoundary mixedBoundary completeFrame && completeFrame.inputs.size == mixed.size)
    "complete mixed project public capture changed its original/private boundary"
  check ((← (List.range 16).toArray.mapM project.current).map (·.head) == expected) "audit changed original heads"
  let report := Json.mkObj [("allPassed",toJson true),("sources",toJson view.sources.size),
    ("timings",toJson timings),("sameOriginalReadinessAdvance",toJson true),
    ("privateUsageAttachedSeparately",toJson true),("independentFullFrameEqual",toJson true),
    ("readOnlyOriginalPrivateOverlay",toJson true),("completeMixedProjectCapture",toJson true),
    ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") report.pretty
  IO.println report.compress
end Eggshell.Research.PublicInputChecks
