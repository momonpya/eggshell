import tools.research.StudyLocal
open Lean StudyLocal
namespace OwnerViewCensusStudy
def parent := base/"practical-runtime/source-snapshot"
def root := base/"practical-runtime/owner-view-census"
def records := project/"docs/candidates/owner-view-census"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh metadata census required"
  check ((← hash (parent/"build/StudyMain")) == "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534")
    "fixed product parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  IO.FS.writeFile (root/"source/tools/research/OwnerViewCensus.lean")
    (← IO.FS.readFile (project/"tools/research/OwnerViewCensus.lean"))
  IO.FS.writeFile (root/"source/tools/research/CensusProducerWindows.lean")
    (← IO.FS.readFile (project/"tools/research/producer-windows/ProducerWindows.lean"))
  let configuration := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (parent/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.OwnerViewCensus")
  write (root/"settings.json") configuration
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let old ← read (project/"docs/candidates/source-snapshot/llvm/before-delivery.json")
  let domain ← read (project/"docs/candidates/source-snapshot/llvm/diagnostic/domain.json")
  let plan := Json.mkObj [("source",original.getObjValD "source"),("sourceFiles",original.getObjValD "sourceFiles"),
    ("owners",domain.getObjValD "hydrated"),("expectedHead",old.getObjValD "originalHead"),
    ("output",toJson (records/"census.json").toString)]
  write (root/"plan.json") plan
  write (records/"plan.json") (plan.setObjVal! "purpose"
    (toJson "measure actual owner metadata components of the recorded topic-1 view without queries, indexes or answering models"))
  guard "owner-view-census-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def run : IO Unit := do
  idle
  discard <| finished "owner-view-census-checked-build"
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["common-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args)
  guard "owner-view-census" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"build/StudyMain").toString,(root/"plan.json").toString]
def rebuild : IO Unit := do
  idle
  let stopped ← read (base/"owner-view-census-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped census observer"
  write (records/"build-refusal.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/tools_research_OwnerViewCensus-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/tools_research_OwnerViewCensus-lean.stderr"))),
    ("productChanged",toJson false),("databaseOrModelStarted",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/OwnerViewCensus.lean")
    (← IO.FS.readFile (project/"tools/research/OwnerViewCensus.lean"))
  guard "owner-view-census-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    total := (total.1+counts.1,total.2+counts.2)
  IO.FS.removeDir path
  return total
def finish : IO Unit := do
  idle
  let completed ← finished "owner-view-census"
  let result ← read (records/"census.json")
  check (result.getObjValD "sourceHashesBeforeAndAfter" == toJson true &&
    result.getObjValD "actualQueries" == toJson (0 : Nat)) "incomplete readonly metadata census"
  write (records/"guards.json") (toJson #[("build",← read (base/"owner-view-census-build.guard.json")),
    ("checked-build",← finished "owner-view-census-checked-build"),("census",completed)])
  let inputs : Array (String × String) ← IO.ofExcept
    (fromJson? (← read (project/"docs/candidates/source-snapshot/protected-native-inputs.json")))
  check (!(inputs.any fun (path,_) => path.startsWith (root.toString++"/"))) "census cleanup overlaps protected inputs"
  for (path,expected) in inputs do check ((← hash (.mk path)) == expected) "protected input changed before cleanup"
  let counts ← remove root
  for (path,expected) in inputs do check ((← hash (.mk path)) == expected) "cleanup changed a protected input"
  write (records/"cleanup.json") (Json.mkObj [("files",toJson counts.1),("logicalBytes",toJson counts.2),
    ("protectedNativeHashesBeforeAndAfter",toJson inputs.size),("archiveCreated",toJson false),
    ("originalAndCurrentProductRetained",toJson true)])
end OwnerViewCensusStudy
def main : List String → IO Unit
  | ["prepare"] => OwnerViewCensusStudy.prepare
  | ["run"] => OwnerViewCensusStudy.run
  | ["rebuild"] => OwnerViewCensusStudy.rebuild
  | ["finish"] => OwnerViewCensusStudy.finish
  | _ => throw (IO.userError "OwnerViewCensusStudy prepare|run")
