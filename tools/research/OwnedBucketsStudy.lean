import tools.research.StudyLocal
open Lean StudyLocal
def trial := base/"owned-buckets"
def parentBuild := base/"register-rounds-runtime/build"
def source := trial/"source"
def build := trial/"build"
def records := project/"docs/candidates/owned-buckets"
def clean (tag : String) : IO Json := do
  let monitor ← finished tag
  check (monitor.getObjValD "reason" == Json.null && monitor.getObjValD "guardTriggered" == toJson false)
    "guard did not finish normally"
  return monitor
def main (args : List String) : IO Unit := do
  if args == ["setup"] then
    idle
    check (!(← trial.pathExists)) "fresh component trial required"
    check ((← hash (parentBuild/"StudyMain")) == "1153215e50e63191a46b1f80a34d8c2c0d056478b30b81e5c22958d2c1a8c965")
      "audited parent changed"
    IO.FS.createDirAll records
    materialize parentBuild source build "tools.research.OwnedBucketsChecks" "owned-buckets-settings.json"
    for name in ["OwnedBuckets","OwnedBucketsChecks"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean"))
        (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    write (records/"plan.json") (Json.mkObj [("previousTurn",toJson "verified progress:fixed-lane hash reduced16-client wall by11.190%;still not few seconds"),
      ("currentEvidence",toJson "one owned4-client profile;all7 bodies/ACK pass;search ready318-358ms then4654-4837ms remaining;ownerReach array pushes occur below copy_expand_array"),
      ("hypothesis",toJson "lookup then insert retains the previous array while pushing;alter consumes the map before updating its bucket and may remove repeated whole-bucket copies"),
      ("status",toJson "component only;hypothesis must be falsifiable;no pool,cache,ranking or product change"),
      ("proof",toJson "all lawful hash/equality keys,values,initial tables,rows andprobes:complete ordered optional bucket equality;not internal table layout equality"),
      ("nativePlan",toJson "1024/4096/8192rows x1/46owners;AB/BA/AB;retained immutable input shared with a dedicated actor;read input after clock"),
      ("noRetryOf",toJson "old cue bucket,record-incidence,selector-only pool or full unchanged hook load"),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "owned-buckets-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"owned-buckets-settings.json").toString]
    write (records/"current-build.json") (toJson "owned-buckets-build")
  else if args.head? == some "build" then
    let [_,label] := args | throw (IO.userError "build <fresh label>")
    check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "invalid build label"
    idle
    for name in ["OwnedBuckets","OwnedBucketsChecks"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean"))
        (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    let tag := "owned-buckets-build-"++label
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"owned-buckets-settings.json").toString]
    write (records/"current-build.json") (toJson tag)
  else if args.head? == some "audit" then
    let [_,label] := args | throw (IO.userError "audit <fresh label>")
    check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "invalid audit label"
    discard <| clean (← IO.ofExcept ((← read (records/"current-build.json")).getStr?))
    let tag := "owned-buckets-audit-"++label
    guard tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/OwnedBucketsStudy.lean").toString,"audit-worker"]
    write (records/"current-audit.json") (toJson tag)
  else if args == ["audit-worker"] then
    let tag ← IO.ofExcept ((← read (records/"current-audit.json")).getStr?)
    let nativeName := if tag == "owned-buckets-audit" then "native.json" else
      "native-"++(tag.drop "owned-buckets-audit-".length).toString++".json"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",build.toString,(records/nativeName).toString]
    let names := #["tools.research.OwnedBuckets","tools.research.OwnedBucketsChecks"]
    let modules : Array Json ← IO.ofExcept ((← read (build/"build.json")).getObjValAs? (Array Json) "modules")
    check (modules.size == names.size && modules.all (fun row => names.contains ((row.getObjValAs? String "module").toOption.getD "")))
      "component unexpectedly links a product implementation"
    let mut witnesses := #[]
    for name in names do
      let (text,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (build/(name.replace "." "_"++".source"))))
      let path := project/(name.replace "." "/"++".lean")
      check (text == (← IO.FS.readFile path) && literals.isEmpty) "native helper is not the reviewed source"
      witnesses := witnesses.push (name,← hash path)
    IO.FS.writeFile (records/"axioms.txt") (← IO.FS.readFile (build/"tools_research_OwnedBuckets-lean.stdout"))
    let symbols ← command "/usr/bin/nm" #["-n",(build/"tools_research_OwnedBucketsChecks.o").toString]
    check (symbols.contains "OwnedBuckets_reference___at___00OwnedBucketsChecks_before" &&
      symbols.contains "OwnedBuckets_exclusive___at___00OwnedBucketsChecks_after" &&
      symbols.contains "_l_OwnedBucketsChecks_before\n" && symbols.contains "_l_OwnedBucketsChecks_after\n")
      "native test does not define both distinct specialized constructor paths"
    IO.FS.writeFile (records/"consumer-symbols.txt") symbols
    write (records/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("helperSources",toJson witnesses),("nativeAudit",toJson nativeName),("componentOnly",toJson true),("adopted",toJson false)])
  else if args == ["run"] then
    discard <| clean (← IO.ofExcept ((← read (records/"current-audit.json")).getStr?))
    check ((← read (records/"runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "audited component changed"
    guard "owned-buckets-component" #[(build/"StudyMain").toString,(trial/"run").toString]
  else if args == ["collect"] then
    let monitor ← clean "owned-buckets-component"
    write (records/"component.json") (Json.mkObj [("guard",monitor),("report",← read (trial/"run/report.json")),
      ("runtimeSha256",toJson (← hash (build/"StudyMain"))),("adopted",toJson false)])
  else throw (IO.userError "setup|build <label>|audit <label>|run|collect")
