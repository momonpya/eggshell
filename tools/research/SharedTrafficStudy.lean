import tools.research.StudyLocal
open Lean StudyLocal
namespace SharedTrafficStudy

def practical := base/"practical-runtime"
def parent := practical/"coordinated-warm"
def root := practical/"shared-traffic"
def records := project/"docs/practical-runtime/shared-traffic"

def prepare (registered : Bool := false) : IO Unit := do
  idle
  let root := if registered then practical/"registered-hooks" else root
  let records := if registered then project/"docs/practical-runtime/registered-hooks" else records
  check (!(← root.pathExists)) "preserve existing mixed-traffic trial"
  check (!(← (records/"plan.json").pathExists)) "preserve the sealed previous traffic plan"
  check ((← hash (parent/"build/StudyMain")) ==
    "0411e4921419b4948f97aebdb6436a3c2de92087c150f15515d2eb67f7545fec") "fixed shared product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  for name in ["source","build"] do
    discard <| command "/bin/cp" #["-cR",(parent/name).toString,(root/name).toString]
  for name in ["SharedTrafficChecks.lean","SharedProjectLifecycle.lean","RegisteredHook.lean"] do
    IO.FS.writeFile (root/"source/tools/research"/name) (← IO.FS.readFile (project/"tools/research"/name))
  let entry := root/"source/tools/research/StudyMain.lean"
  let original ← IO.FS.readFile entry
  let marker := "  | other => sourceRouteEngine other"
  check ((original.splitOn marker).length == 2) "native controller dispatcher changed"
  IO.FS.writeFile entry ("import tools.research.SharedTrafficChecks\n" ++ original.replace marker
    ("  | [\"shared-traffic\",input,directory] => Eggshell.Research.SharedTrafficChecks.run input directory; return 0\n"++marker))
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"build-settings.json") settings
  write (records/"plan.json") (Json.mkObj [("productSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("waves",toJson (3 : Nat)),("simultaneousClients",toJson (if registered then 10 else (16 : Nat))),("writers",toJson (4 : Nat)),
    ("activeReaders",toJson (if registered then 3 else (6 : Nat))),("llvmReaders",toJson (if registered then 3 else (6 : Nat))),
    ("registeredCommands",toJson registered),("manualKeepUsed",toJson (!registered)),
    ("registry",← read (parent/"prefix/plugins/eggshell/hooks/hooks.json")),
    ("llvmTopics",toJson #[1,2,3]),("hookDeadlineMs",toJson (30000 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("seedAccepted",toJson false),("adopted",toJson false),
    ("passRequiresAllFrozenEvidence",toJson true),("numericalFallbackReportedSeparately",toJson true)])
  guard (if registered then "practical-registered-hooks-build" else "practical-shared-traffic-build") #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def rebuild (previous next : String) (registered : Bool := false) : IO Unit := do
  idle
  let root := if registered then practical/"registered-hooks" else root
  let stopped ← read (base/(previous++".guard.json"))
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous compiler still owns processes"
  IO.FS.writeFile (root/"source/tools/research/SharedTrafficChecks.lean")
    (← IO.FS.readFile (project/"tools/research/SharedTrafficChecks.lean"))
  for name in ["SharedProjectLifecycle.lean","RegisteredHook.lean"] do
    IO.FS.writeFile (root/"source/tools/research"/name) (← IO.FS.readFile (project/"tools/research"/name))
  let entry := root/"source/tools/research/StudyMain.lean"
  let original ← IO.FS.readFile entry
  let marker := "  | other => sourceRouteEngine other"
  check ((original.splitOn marker).length == 2) "native controller dispatcher changed"
  let mut updated := original
  for action in [
      "  | [\"shared-traffic-inspect\",directory,report] => Eggshell.Research.SharedTrafficChecks.inspect directory report; return 0\n",
      "  | [\"shared-traffic-resume\",input,directory,report] => Eggshell.Research.SharedTrafficChecks.resume input directory report; return 0\n",
      "  | \"audit\"::rest => NativeTrialAudit.cliMain rest; return 0\n"] do
    unless updated.contains action do updated := updated.replace marker (action++marker)
  IO.FS.writeFile entry updated
  guard next #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def run (directory tag buildTag : String) (prepared : Option String := none) (readers : Nat := 6)
    (registered : Bool := false) : IO Unit := do
  idle
  let root := if registered then practical/"registered-hooks" else root
  let records := if registered then project/"docs/practical-runtime/registered-hooks" else records
  discard <| finished buildTag
  let output := root/directory
  let previous ← read (parent/"owner-lifecycle-input.json")
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
  let env := env.filter (fun row => !["EGGSHELL_DATA_ROOT","TMPDIR"].contains row.1) ++ #[
    ("EGGSHELL_DATA_ROOT",some (output/"data").toString),("TMPDIR",some (root/"tmp").toString)]
  IO.FS.createDirAll (root/"tmp")
  let seed ← read (practical/"cohort/study/seed-1/plan.json")
  let frozen ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let specification := Json.mkObj [("installation",previous.setObjVal! "environment" (toJson env)),
    ("original",frozen.getObjValD "source"),("originalFiles",frozen.getObjValD "sourceFiles"),
    ("workspace",seed.getObjValD "workspace"),
    ("definitions",← read (practical/"interrupted-recovery/definitions.json")),("preparedReference",toJson prepared),
    ("activeReaders",toJson readers),("llvmReaders",toJson readers),("registered",toJson registered)]
  let input := root/(directory++"-input.json")
  check (!(← input.pathExists)) "preserve sealed mixed-traffic admission"
  write input specification
  write (records/(directory++"-plan.json")) (Json.mkObj [("clients",toJson (4+2*readers)),
    ("writers",toJson (4 : Nat)),("activeReaders",toJson readers),("llvmReaders",toJson readers),
    ("waves",toJson (3 : Nat)),("product",(previous.getObjValD "runtime")),("registeredCommands",toJson registered),
    ("fullAuditsAfterServicesStop",toJson true),("sameSnapshot",toJson true),
    ("priorAttemptsNotPooled",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  guard tag (#["/usr/bin/env"] ++ unset.flatMap (fun key => #["-u",key]) ++
    assigned ++ #[(root/"build/StudyMain").toString,"shared-traffic",input.toString,output.toString])

def retain (registered : Bool := false) : IO Unit := do
  idle
  let root := if registered then practical/"registered-hooks" else root
  let records := if registered then project/"docs/practical-runtime/registered-hooks" else records
  let monitor ← finished (if registered then "practical-registered-hooks-native" else "practical-shared-traffic-local")
  let area := root/(if registered then "run" else "local")
  let result ← read (area/"result.json")
  let waves ← IO.ofExcept (result.getObjValAs? (Array Json) "waves")
  check (waves.size == 3 && result.getObjValD "clientsPerWave" == toJson (10 : Nat))
    "the complete declared local series is required"
  IO.FS.createDirAll (records/"bodies")
  IO.FS.createDirAll (records/"responses")
  let mut queries := #[]
  let mut summaries := #[]
  let mut saves := #[]
  for wave in waves do
    let number ← IO.ofExcept (wave.getObjValAs? Nat "wave")
    let outcomes ← IO.ofExcept (wave.getObjValAs? (Array Json) "outcomes")
    let mut semantic := 0
    let mut maxHook := 0
    let mut maxWriter := 0
    let mut intervals : Array (Nat × Nat) := #[]
    let mut readerIntervals : Array (Nat × Nat) := #[]
    for outcome in outcomes do
      if outcome.getObjValD "kind" == toJson "writer" then
        let session ← IO.ofExcept ((outcome.getObjValD "output").getObjValAs? String "session")
        let first ← IO.ofExcept (outcome.getObjValAs? Nat "startedMs")
        let last ← IO.ofExcept (outcome.getObjValAs? Nat "finishedMs")
        maxWriter := max maxWriter (last-first)
        intervals := intervals.push (first,last)
        let mut calls := []
        for label in ["read-pre","read-post","consume-pre","consume-post","detail-pre","detail-post","stop","keep"] do
          let folder := area/"calls"/session/label
          if !(← folder.pathExists) then continue
          let registration ← if ← (folder/"registration.json").pathExists then read (folder/"registration.json") else pure Json.null
          calls := calls ++ [(label,Json.mkObj [("timing",← read (folder/"record.json")),
            ("stderr",toJson (← IO.FS.readFile (folder/"stderr"))),("registration",registration)])]
        saves := saves.push (Json.mkObj [("wave",toJson number),("operation",outcome),("calls",Json.mkObj calls)])
        continue
      let row := outcome.getObjValD "delivery"
      let session ← IO.ofExcept (row.getObjValAs? String "session")
      let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
      maxHook := max maxHook elapsed
      readerIntervals := readerIntervals.push (← IO.ofExcept (row.getObjValAs? Nat "startedMs"),
        ← IO.ofExcept (row.getObjValAs? Nat "finishedMs"))
      if (row.getObjValD "search").getObjValD "semantic" == toJson "completed" then semantic := semantic+1
      let body ← IO.ofExcept (row.getObjValAs? String "body")
      let digest ← IO.ofExcept (row.getObjValAs? String "bodySha256")
      check ((← hash (.mk body)) == digest) "actual body changed before retention"
      let retained := records/"bodies"/(digest++".txt")
      if !(← retained.pathExists) then IO.FS.writeBinFile retained (← IO.FS.readBinFile (.mk body))
      check ((← hash retained) == digest) "deduplicated body differs"
      let call := area/"calls"/session/"prompt"
      let timing ← read (call/"record.json")
      let stdoutHash ← hash (call/"stdout")
      check (timing.getObjValD "stdoutSha256" == toJson stdoutHash) "actual stdout differs from native timing receipt"
      let response := records/"responses"/(stdoutHash++".json")
      if !(← response.pathExists) then IO.FS.writeBinFile response (← IO.FS.readBinFile (call/"stdout"))
      queries := queries.push (Json.mkObj [("wave",toJson number),("kind",outcome.getObjValD "kind"),
        ("topic",outcome.getObjValD "topic"),("delivery",row),("request",← read (call/"stdin")),
        ("timing",timing),("retainedBody",toJson retained.toString),("retainedStdout",toJson response.toString)])
    let overlap := intervals.all fun (first,last) => readerIntervals.any fun (a,b) => first < b && a < last
    let audit := wave.getObjValD "llvmAudits"
    let automatic ← if ← (area/s!"wave-{number}-auto-answers.json").pathExists then
        read (area/s!"wave-{number}-auto-answers.json") else pure Json.null
    let fast ← if ← (area/s!"wave-{number}-fast-events.json").pathExists then
        read (area/s!"wave-{number}-fast-events.json") else pure Json.null
    let facts ← if ← (area/s!"wave-{number}-facts.json").pathExists then
        read (area/s!"wave-{number}-facts.json") else pure Json.null
    summaries := summaries.push (Json.mkObj [("wave",toJson number),("elapsedMs",wave.getObjValD "elapsedMs"),
      ("readers",toJson readerIntervals.size),("semanticCompleted",toJson semantic),("maxHookMs",toJson maxHook),
      ("maxWriterSequenceMs",toJson maxWriter),("writerOperationsOverlapReaders",toJson overlap),
      ("census",← read (area/s!"wave-{number}-census.json")),("llvmAudits",audit),
      ("automaticAnswers",automatic),("fastEvents",fast),("synapses",facts),
      ("drainTiming",← read (area/s!"wave-{number}-ready/record.json"))])
  write (records/"result.json") (Json.mkObj [("native",result),("guard",monitor),("summary",toJson summaries),
    ("queries",toJson queries),("saves",toJson saves),("productUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  write (records/"frozen-before-delivery.json") (← read (area/"frozen-before-delivery.json"))
  write (records/"stopped.json") (Json.mkObj [("frontend",← read (area/"frontend-stop.json")),
    ("publisher",← read (area/"publisher-stop.json"))])
  if !registered then
    let mut attempts := []
    for (name,tag) in [("wrong-workspace","practical-shared-traffic-native"),
        ("audit-during-traffic","practical-shared-traffic-checked"),("sixteen-clients","practical-shared-traffic-bounded")] do
      attempts := attempts ++ [(name,← read (base/(tag++".guard.json")))]
    write (records/"earlier-attempts.json") (Json.mkObj attempts)

def retainProfiles (registered : Bool := false) : IO Unit := do
  idle
  let root := if registered then practical/"registered-hooks" else root
  let records := if registered then project/"docs/practical-runtime/registered-hooks" else records
  discard <| finished (if registered then "practical-registered-hooks-native" else "practical-shared-traffic-local")
  let mut rows := #[]
  for entry in ← (root/(if registered then "run" else "local")/"data/receipts").readDir do
    let path := entry.path/"request.json"
    if !(← path.pathExists) then continue
    let request := (← read path).getObjValD "data"
    let session := (request.getObjValAs? String "session").toOption.getD ""
    let event := (request.getObjValAs? String "event").toOption.getD ""
    if !["traffic-1-","traffic-2-","traffic-3-"].any (fun start => session.startsWith start) ||
        !["PreToolUse","PostToolUse"].contains event then continue
    let transport := (← read (entry.path/"transport.json")).getObjValD "data"
    let dispatch := (← read (entry.path/"dispatch.json")).getObjValD "data"
    let published := (← read (entry.path/"published.json")).getObjValD "data"
    rows := rows.push (Json.mkObj [("session",toJson session),("event",toJson event),
      ("transport",transport),("dispatch",dispatch),
      ("parentStartedMs",published.getObjValD "startedMs"),("parentFlushedMs",published.getObjValD "flushedMs"),
      ("stdoutSha256",published.getObjValD "sha256")])
  check (rows.size == 72) "retain all twelve writers' three Pre/Post pairs"
  write (records/"hook-profiles.json") (toJson rows)

def retainEarlier : IO Unit := do
  idle
  let mut attempts := []
  for name in ["run","checked","bounded"] do
    let area := root/name
    let mut stages := []
    for wave in [1,2,3] do
      for kind in ["outcomes","audits","census"] do
        let path := area/s!"wave-{wave}-{kind}.json"
        if ← path.pathExists then
          let value ← try read path catch _ => pure (Json.mkObj [("incompleteFileSha256",toJson (← hash path))])
          stages := stages ++ [(s!"wave-{wave}-{kind}",value)]
    attempts := attempts ++ [(name,Json.mkObj stages)]
  write (records/"earlier-traffic.json") (Json.mkObj attempts)

def reuseExisting (registered : Bool := false) : IO Unit := do
  idle
  let records := if registered then project/"docs/practical-runtime/registered-hooks" else records
  let result ← read (records/"result.json")
  let mut queries := #[]
  let mut removed : Array String := #[]
  let mut matched := #[]
  for row in ← IO.ofExcept (result.getObjValAs? (Array Json) "queries") do
    if row.getObjValD "kind" != toJson "llvm-reader" then
      queries := queries.push row
      continue
    let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
    let earlier := project/"docs/practical-runtime/recovery"/s!"topic-{topic}"
    let body ← IO.ofExcept (row.getObjValAs? String "retainedBody")
    let response ← IO.ofExcept (row.getObjValAs? String "retainedStdout")
    let bodyHash := (row.getObjValD "delivery").getObjValD "bodySha256"
    let stdoutHash := (row.getObjValD "timing").getObjValD "stdoutSha256"
    check (bodyHash == toJson (← hash (earlier/"body.txt")) && bodyHash == toJson (← hash (.mk body)))
      "same-snapshot healthy baseline and current body differ"
    check (stdoutHash == toJson (← hash (earlier/"stdout.json")) && stdoutHash == toJson (← hash (.mk response)))
      "same-snapshot actual stdout differs"
    queries := queries.push (row.setObjVal! "retainedBody" (toJson (earlier/"body.txt").toString)
      |>.setObjVal! "retainedStdout" (toJson (earlier/"stdout.json").toString))
    if !removed.contains body then
      removed := removed.push body |>.push response
      matched := matched.push (Json.mkObj [("topic",toJson topic),("bodySha256",bodyHash),("stdoutSha256",stdoutHash)])
  check (matched.size == 3) "all three LLVM bodies required"
  write (records/"result.json") (result.setObjVal! "queries" (toJson queries))
  for path in removed do
    check (path.startsWith (records.toString++"/")) "never remove the retained baseline"
    IO.FS.removeFile (.mk path)
  write (records/"shared-bodies.json") (Json.mkObj [("matches",toJson matched),
    ("removedDuplicateFiles",toJson removed.size),("currentHookCallsReplaced",toJson false),
    ("sameBytesFromIndependentCurrentRequests",toJson true),("speedOrTokenComparison",toJson false)])

def tidyAudits : IO Unit := do
  idle
  let names := ["native-controller.json","sources.json","native-separated.json","sources-separated.json"]
  let mut audits := []
  for name in names do audits := audits ++ [(name,← read (records/name))]
  let earlier ← read (records/"earlier-attempts.json")
  write (records/"earlier-attempts.json") (earlier.setObjVal! "compilerAudits" (Json.mkObj audits))
  for name in names do IO.FS.removeFile (records/name)

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      total := (total.1+part.1,total.2+part.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)

def cleanup (registered : Bool := false) : IO Unit := do
  idle
  let root := if registered then practical/"registered-hooks" else root
  let records := if registered then project/"docs/practical-runtime/registered-hooks" else records
  discard <| finished (if registered then "practical-registered-hooks-native" else "practical-shared-traffic-local")
  check (!(← (records/"retired.json").pathExists)) "preserve previous retirement"
  let measured ← read (records/"result.json")
  let queries ← IO.ofExcept (measured.getObjValAs? (Array Json) "queries")
  check (queries.size == 18 && (← (records/"hook-profiles.json").pathExists))
    "retain current evidence before deleting experiment data"
  for row in queries do
    let body ← IO.ofExcept (row.getObjValAs? String "retainedBody")
    let stdout ← IO.ofExcept (row.getObjValAs? String "retainedStdout")
    check ((row.getObjValD "delivery").getObjValD "bodySha256" == toJson (← hash (.mk body))) "retained body changed"
    check ((row.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (.mk stdout))) "retained stdout changed"
  let frozen ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let source ← IO.ofExcept (frozen.getObjValAs? String "source")
  let sourceFiles : Array (String × String) ← IO.ofExcept (frozen.getObjValAs? _ "sourceFiles")
  let artifacts := #[parent/"build/StudyMain",practical/"build/StudyMain",
    base/"canonical-decoder-runtime/build/StudyMain",practical/"package/prefix/libexec/eggshell"]
  let before ← artifacts.mapM fun path => do pure (path,← hash path)
  for (name,digest) in sourceFiles do check ((← hash (.mk source/name)) == digest) "protected original changed"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => line.trimAscii.toString.startsWith (base.toString++"/"))
    "experiment service or client remains live"
  for build in [parent/"build",practical/"build",base/"canonical-decoder-runtime/build"] do
    for line in (← IO.FS.readFile (build/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if path.isAbsolute then
        check (!(← IO.FS.realPath path).toString.startsWith (root.toString++"/")) "current runtime depends on ended controller"
  check (!(← IO.FS.realPath (parent/"prefix/share/eggshell/minilm")).toString.startsWith (root.toString++"/"))
    "current model assets depend on ended experiment"
  let removed ← remove root
  for (path,digest) in before do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in sourceFiles do check ((← hash (.mk source/name)) == digest) "protected original changed during retirement"
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("originalAndRuntimeHashesUnchanged",toJson true),
    ("currentNativeInputsAndModelOutsideRetiredDirectory",toJson true)])

def main : List String → IO Unit
  | ["prepare"] => prepare
  | ["rebuild",previous,next] => rebuild previous next
  | ["run",directory,tag,buildTag] => run directory tag buildTag
  | ["run",directory,tag,buildTag,prepared] => run directory tag buildTag (some prepared)
  | ["run-local",directory,tag,buildTag,prepared] => run directory tag buildTag (some prepared) 3
  | ["retain"] => retain
  | ["retain-profiles"] => retainProfiles
  | ["retain-earlier"] => retainEarlier
  | ["reuse-existing"] => reuseExisting
  | ["tidy-audits"] => tidyAudits
  | ["cleanup"] => cleanup
  | ["prepare-registered"] => prepare true
  | ["rebuild-registered",previous,next] => rebuild previous next true
  | ["run-registered",buildTag] => run "run" "practical-registered-hooks-native" buildTag none 3 true
  | ["retain-registered"] => retain true
  | ["profiles-registered"] => retainProfiles true
  | ["reuse-registered"] => reuseExisting true
  | ["cleanup-registered"] => cleanup true
  | _ => IO.println "SharedTrafficStudy prepare | run"
end SharedTrafficStudy
def main := SharedTrafficStudy.main
