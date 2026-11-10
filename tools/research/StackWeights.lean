import tools.research.StudyLocal
open Lean StudyLocal

structure Frame where
  depth : Nat
  count : Nat
  name : String
  image : String
  children : Nat := 0

def Frame.key (frame : Frame) : String := frame.name++"  (in "++frame.image++")"

def parseFrame (line : String) : Option Frame := do
  let chars := line.toList
  let leader := chars.takeWhile (!·.isDigit)
  unless leader.all (fun c => [' ','+','!',':','|','.'].contains c) do none
  let tail := chars.drop leader.length
  let digits := tail.takeWhile Char.isDigit
  let count ← (String.ofList digits).toNat?
  let rest := (String.ofList (tail.drop digits.length)).trimAscii.toString
  let [name,location] := rest.splitOn "  (in " | none
  let image := (location.splitOn ")").head!
  return ⟨leader.length,count,name,image,0⟩

def add (values : Std.HashMap String Nat) (name : String) (count : Nat) : Std.HashMap String Nat :=
  values.insert name (values[name]?.getD 0+count)

structure Summary where
  stack : List Frame := []
  exclusive : Std.HashMap String Nat := {}
  inclusive : Std.HashMap String Nat := {}
  frames : Nat := 0
  inconsistent : Nat := 0
  issues : Array (String × Nat × Nat × Nat) := #[]

def finish (state : Summary) : Summary := match state.stack with
  | [] => state
  | top :: rest =>
    {state with
      stack := match rest with
        | [] => []
        | parent :: rest => {parent with children := parent.children+top.count} :: rest
      exclusive := add state.exclusive top.key (top.count-top.children)
      inconsistent := state.inconsistent+(if top.children > top.count then 1 else 0)
      issues := if top.children > top.count && state.issues.size < 10 then
        state.issues.push (top.name,top.depth,top.count,top.children) else state.issues}

def flush (state : Summary) : Summary :=
  state.stack.length.fold (fun _ _ state => finish state) state

def insert (state : Summary) (frame : Frame) : Summary := Id.run do
  let mut state := state
  for _ in [:state.stack.length] do
    match state.stack with
    | [] => break
    | top :: _ => if top.depth ≥ frame.depth then state := finish state else break
  let already := state.stack.any (·.key == frame.key)
  return {state with
    stack := frame :: state.stack
    inclusive := if already then state.inclusive else add state.inclusive frame.key frame.count
    frames := state.frames+1}

def ranked (values : Std.HashMap String Nat) (predicate : String → Bool := fun _ => true) : Array Json :=
  (((values.toArray.filter fun row => row.2 > 0 && predicate row.1).qsort fun a b =>
    if a.2 == b.2 then a.1 < b.1 else a.2 > b.2).take 45).map fun (name,count) =>
      Json.mkObj [("name",toJson name),("sampleWeight",toJson count)]

def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "sample.txt new-output.json")
  let path : System.FilePath := .mk output
  check (!(← path.pathExists)) "never overwrite a collected profile"
  let text ← IO.FS.readFile (.mk input)
  let mut state : Summary := {}
  let [_,graphAndTail] := text.splitOn "Call graph:\n" | throw (IO.userError "one call graph required")
  let [graph,_] := graphAndTail.splitOn "Total number in stack" | throw (IO.userError "one graph summary boundary required")
  for line in graph.splitOn "\n" do
    if line.contains "Thread_" then state := flush state
    else if let some frame := parseFrame line then state := insert state frame
  state := flush state
  check (state.frames > 0 && state.inconsistent == 0)
    ("profile tree counts do not form a valid forest: "++(toJson state.issues).compress)
  let [_,footer] := text.splitOn "Sort by top of stack, same collapsed (when >= 5):\n" |
    throw (IO.userError "one native exclusive summary required")
  let [table,_] := footer.splitOn "Binary Images:" | throw (IO.userError "one summary boundary required")
  let mut compared := 0
  for line in table.splitOn "\n" do
    let [name,location] := line.trimAscii.toString.splitOn "  (in " | continue
    let key := name++"  (in "++(location.splitOn ")").head!++")"
    let countText := String.ofList (line.trimAscii.toString.toList.reverse.takeWhile Char.isDigit).reverse
    let some count := countText.toNat? | throw (IO.userError "exclusive summary lacks its count")
    check (state.exclusive[key]?.getD 0 == count) ("native exclusive summary differs: "++key++
      "; calculated="++toString (state.exclusive[key]?.getD 0)++"; native="++toString count)
    compared := compared+1
  check (compared > 0) "non-vacuous comparison with native summary required"
  let relevant := fun name => name.contains "Synaptic" || name.contains "PageMap" || name.contains "Binding" ||
    name.contains "Prepared" || name.contains "indexedDiscovery" || name.contains "selectSource" ||
    name.contains "Rendering" || name.contains "PlanMetadata"
  write path (Json.mkObj [("input",toJson input),("inputSha256",toJson (← hash (.mk input))),
    ("frames",toJson state.frames),("inconsistentParents",toJson state.inconsistent),
    ("nativeExclusiveSummaryEntriesCompared",toJson compared),
    ("symbolIdentityIncludesImage",toJson true),
    ("exclusive",toJson (ranked state.exclusive)),("relevantInclusive",toJson (ranked state.inclusive relevant)),
    ("weightsAreCpuPercentagesOrDurations",toJson false),("waitingThreadsIncluded",toJson true),
    ("recursionCollapsedForInclusiveWeights",toJson true)])
