import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def main (args : List String) : IO Unit := do
  let mode::tag::rest := args | throw (IO.userError "mode and unique tag required")
  for entry in ← base.readDir do
    if (["front-traffic-","front-input-","front-manager-"].any (fun stem => entry.fileName.startsWith stem)) && entry.fileName.endsWith ".guard.json" then
      let value ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "prior work is still owned")
  unless tag.startsWith "front-input-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve previous work")
  let command ← if mode == "build" then do
      -- Only our two checker modules cross into the isolated source tree.
      -- The production core remains the separately edited candidate.
      for name in ["FrontTrafficChecks.lean","FrontInputAudit.lean"] do
        let source ← IO.FS.readFile (workspace/"tools/research"/name)
        let target := base/"interest-traffic-core/tools/research"/name
        IO.FS.writeFile target source
        unless (← IO.FS.readFile target) == source do
          throw (IO.userError "checker source copy changed")
      let old ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"front-traffic-build-settings.json")))
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"front-traffic-build"
      let config := old.setObjVal! "baselineCore" (toJson (base/"front-input-baseline-core").toString)
        |>.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "output" (toJson (base/"front-input-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      IO.FS.writeFile (base/"front-input-build-settings.json") config.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
        "-M1024","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,(base/"front-input-build-settings.json").toString]
    else if ["proofs","contract"].contains mode then do
      let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"front-input-build-settings.json")))
      let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
      let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
      let paths := #[(base/"front-input-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
      let source := if mode == "proofs" then workspace/"tools/research/NativeMetadataProofs.lean"
        else base/"interest-traffic-core/Eggshell/ContractAudit.lean"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
        toolchain++"/bin/lean","-M1024",source.toString]
    else if mode == "sample-startup" then do
      let [fixture] := rest | throw (IO.userError "controlled fixture required")
      unless fixture.startsWith "front-input-fixture-" do throw (IO.userError "controlled fixture prefix required")
      let root := base/fixture
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M512","--run",
        (workspace/"docs/candidates/front-input/startup-probe.lean").toString,
        (base/"front-input-build/StudyMain").toString,root.toString]
    else if ["audit","retry","recovery","key","startup"].contains mode then do
      let [fixture] := rest | throw (IO.userError "retained fixture required")
      unless fixture.startsWith "front-input-fixture-" do throw (IO.userError "controlled fixture prefix required")
      let root := base/fixture
      let action := if mode == "audit" then "front-input-audit" else if mode == "retry" then "front-input-retry"
        else if mode == "key" || mode == "startup" then "front-input-key-checks" else "front-input-recovery-checks"
      let command := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        (base/"front-input-build/StudyMain").toString,action,root.toString]
      pure (if mode == "startup" then #["/usr/bin/time","-p"]++command else command)
    else if mode == "run" then do
      let [fixture] := rest | throw (IO.userError "fresh fixture required")
      unless fixture.startsWith "front-input-fixture-" do throw (IO.userError "controlled fixture prefix required")
      let root := base/fixture
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"front-input-build/StudyMain").toString,
        "front-input-diagnostic",root.toString,"8"]
    else throw (IO.userError "build/run required")
  let config := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) config.pretty
