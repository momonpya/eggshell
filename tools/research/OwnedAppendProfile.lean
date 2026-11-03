import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap

open Lean

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def endpointPid (root : System.FilePath) (child : IO.Process.Child cfg) : IO Nat := do
  let deadline := (← IO.monoMsNow)+10000
  repeat
    let endpoint := root / "private/publisher/endpoint.json"
    if ← endpoint.pathExists then
      let encoded ← IO.ofExcept (Json.parse (← IO.FS.readFile endpoint))
      let pid : Nat ← IO.ofExcept (encoded.getObjValAs? _ "pid")
      let parent ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","ppid="]}
      check (parent.exitCode == 0 && parent.stdout.trimAscii.copy == toString child.pid.toNat)
        "profiling target is not the native audit's service child"
      return pid
    if let some code ← child.tryWait then throw (IO.userError s!"native audit exited before sampling: {code}")
    check ((← IO.monoMsNow) < deadline) "native service endpoint did not become live"
    IO.sleep 5
  throw (IO.userError "unreachable native endpoint wait")

private def waitBounded (child : IO.Process.Child cfg) (deadline : Nat) : IO UInt32 := do
  repeat
    if let some code ← child.tryWait then return code
    check ((← IO.monoMsNow) < deadline) "native append diagnostic exceeded its overall bound"
    IO.sleep 5
  throw (IO.userError "unreachable native diagnostic wait")

private def audit (binary pathText : String) : IO Unit := do
  let root := System.FilePath.mk pathText
  check ((System.FilePath.mk binary).isAbsolute && root.isAbsolute && !(← root.pathExists))
    "absolute audit binary and fresh profile root required"
  let child ← IO.Process.spawn {
    cmd := binary,args := #["audit",binary,pathText,"50000"]
    env := #[("LEAN_NUM_THREADS",some "1"),("EGGSHELL_DATA_ROOT",some (root / "controller-private").toString)]
    setsid := true,stdout := .piped,stderr := .piped}
  let out ← IO.asTask child.stdout.readToEnd .dedicated
  let err ← IO.asTask child.stderr.readToEnd .dedicated
  let exited ← IO.mkRef false
  try
    let pid ← endpointPid root child
    let begun ← IO.monoMsNow
    let profile ← IO.asTask (IO.Process.output {
      cmd := "/usr/bin/sample",args := #[toString pid,"5","5","-file",(root / "append.sample").toString]
      stdout := .piped,stderr := .piped}) .dedicated
    let code ← waitBounded child (begun+180000)
    exited.set true
    let sampled ← IO.ofExcept (← IO.wait profile)
    let stdout ← IO.ofExcept (← IO.wait out)
    let stderr ← IO.ofExcept (← IO.wait err)
    check (code == 0 && stderr.isEmpty) s!"native append audit failed: {stderr}"
    check (sampled.exitCode == 0 && (← (root / "append.sample").pathExists))
      s!"native stack sampling failed: {sampled.stderr}"
    let audit ← IO.ofExcept (Json.parse stdout)
    let report := Json.mkObj [("diagnosticOnly",toJson true),("sampledServicePid",toJson pid),
      ("sampleDurationSeconds",toJson (5 : Nat)),("sampleIntervalMs",toJson (5 : Nat)),
      ("observationMs",toJson ((← IO.monoMsNow)-begun)),("nativeAudit",audit),
      ("samplingPerturbsLatency",toJson true),("notAnAdoptionComparison",toJson true)]
    IO.FS.writeFile (root / "profile.json") (report.pretty ++ "\n")
    IO.println (Json.mkObj [("passed",toJson true),("report",toJson (root / "profile.json").toString)]).compress
  finally
    unless ← exited.get do
      try child.kill catch _ => pure ()
      let _ ← child.wait
      let _ ← IO.wait out
      let _ ← IO.wait err

private structure Frame where
  depth : Nat
  count : Nat
  children : Nat := 0
  symbol : String

private structure Summary where
  stack : Array Frame := #[]
  awake : Std.HashMap String Nat := {}
  blocked : Std.HashMap String Nat := {}
  awakeWeight : Nat := 0
  blockedWeight : Nat := 0

private def blocked (symbol : String) : Bool :=
  ["wait","kevent","mach_msg","nanosleep","select","semaphore"].any fun needle => symbol.contains needle

/-- Attribute only a node's exclusive weight to its ancestor symbols. Repeated
recursive frames count once. Kernel waiting is reported separately from awake
stacks; neither weight is elapsed time or a CPU-time measurement. -/
private def closeOne (summary : Summary) : Summary := Id.run do
  let some frame := summary.stack.back? | return summary
  let mut summary := {summary with stack := summary.stack.pop}
  let weight := frame.count-frame.children
  if weight > 0 then
    let symbols := (summary.stack.toList.map (·.symbol) ++ [frame.symbol]).eraseDups
    if blocked frame.symbol then
      summary := {summary with
        blockedWeight := summary.blockedWeight+weight
        blocked := symbols.foldl (fun counts name => counts.insert name (counts.getD name 0+weight)) summary.blocked}
    else
      summary := {summary with
        awakeWeight := summary.awakeWeight+weight
        awake := symbols.foldl (fun counts name => counts.insert name (counts.getD name 0+weight)) summary.awake}
  if let some parent := summary.stack.back? then
    summary := {summary with stack := summary.stack.pop.push {parent with children := parent.children+frame.count}}
  return summary

private def frame? (line : String) : Option Frame := do
  let chars := line.toList
  let leading := chars.takeWhile (!·.isDigit)
  guard (leading.all fun c => " +!:|".contains c)
  let tail := chars.drop leading.length
  let digits := tail.takeWhile (·.isDigit)
  let count ← (String.ofList digits).toNat?
  let text := (String.ofList (tail.drop digits.length)).trimAscii.copy
  let symbol := (text.splitOn "  (in ").headD text
  guard (text.contains "  (in ")
  return {depth := leading.length,count,symbol}

private def summarize (input output : System.FilePath) : IO Unit := do
  check (input.isAbsolute && output.isAbsolute) "absolute stack summary paths required"
  let mut inside := false
  let mut summary : Summary := {}
  for line in (← IO.FS.readFile input).splitOn "\n" do
    if line.startsWith "Call graph:" then inside := true; continue
    if line.startsWith "Total number in stack" then break
    unless inside do continue
    if (line.trimAscii.copy).contains " Thread_" then
      while !summary.stack.isEmpty do summary := closeOne summary
    else if let some frame := frame? line then
      while summary.stack.back?.any (·.depth ≥ frame.depth) do summary := closeOne summary
      summary := {summary with stack := summary.stack.push frame}
  while !summary.stack.isEmpty do summary := closeOne summary
  let top := fun (counts : Std.HashMap String Nat) =>
    (counts.toArray.qsort (fun a b => a.2 > b.2)).extract 0 50 |>.map fun (symbol,count) =>
      Json.mkObj [("symbol",toJson symbol),("nonrecursiveInclusiveWeight",toJson count)]
  let selected := summary.awake.toArray.filter fun (name,_) =>
    ["Persistence_appendPrepared","Store_Intern","SearchRank_","LogicalText_","Sha256_digest",
     "Blake3_hashSegments","PageMap_Writer_","PageCache_","Wire_encodeList"].any fun needle => name.contains needle
  let result := Json.mkObj [("awakeStackWeight",toJson summary.awakeWeight),
    ("blockedStackWeight",toJson summary.blockedWeight),("awakeTop50",toJson (top summary.awake)),
    ("blockedTop50",toJson (top summary.blocked)),("selectedAwakeFunctions",toJson selected),
    ("weightsAreNotWallOrCpuTime",toJson true),("recursiveFramesDeduplicatedPerStack",toJson true)]
  IO.FS.writeFile output (result.pretty ++ "\n")

def main (args : List String) : IO Unit := do
  match args with
  | ["summary",input,output] => summarize (.mk input) (.mk output)
  | [binary,pathText] => audit binary pathText
  | _ => throw (IO.userError "OwnedAppendProfile NATIVE_AUDIT NEW_ROOT | summary SAMPLE OUTPUT")
