import Main
import Eggshell.ContractAudit
import tools.research.PreparedPlanMetadata
import tools.KeyPostings

open Lean Eggshell Eggshell.Synapses Eggshell.DB
namespace PreparedReadControls

def bindingKey (read : Read) := (read.binding,read.occurrence)
def ownerKey (read : Read) := read.binding.owner

structure Ready where
  rows : Array Read
  bindings : KeyPostings.Index bindingKey rows
  owners : KeyPostings.Index ownerKey rows

/-- The existing eager metadata fold, without selected-owner filtering. This
component bounds avoidable metadata work; it is not a full hook simulation. -/
def rows (descriptors : Array OwnerPalette.Descriptor) : Option (Array Read) :=
  descriptors.foldlM (fun accumulated descriptor => do
    return accumulated ++ (← PreparedPlanMetadata.reads descriptor)) #[]

def prepare (descriptors : Array OwnerPalette.Descriptor) : Option Ready := do
  let values ← rows descriptors
  return ⟨values,KeyPostings.prepare bindingKey values,KeyPostings.prepare ownerKey values⟩

theorem prepared_rows (descriptors : Array OwnerPalette.Descriptor) (ready : Ready)
    (prepared : prepare descriptors = some ready) : rows descriptors = some ready.rows := by
  unfold prepare at prepared
  cases found : rows descriptors with
  | none => simp [found] at prepared
  | some values => simp [found] at prepared; cases prepared; rfl

theorem prepared_binding_lookup (ready : Ready) (key : Binding × Occurrence) :
    ready.bindings.lookup key = ready.rows.filterMap (fun read =>
      if bindingKey read == key then some read else none) := KeyPostings.Index.lookup_exact ..

theorem prepared_owner_lookup (ready : Ready) (owner : String) :
    ready.owners.lookup owner = ready.rows.filterMap (fun read =>
      if ownerKey read == owner then some read else none) := KeyPostings.Index.lookup_exact ..

structure Held where
  ticket : Nat
  ready : Ready

@[noinline] def rebuild (ticket : Nat) (descriptors : Array OwnerPalette.Descriptor) : Option Held := do
  return ⟨ticket,← prepare descriptors⟩

@[noinline] def reuse (ticket : Nat) (ready : Ready) : Held := ⟨ticket,ready⟩

def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty

def ownRss : IO Nat := do
  let pid ← IO.Process.getPID
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-o","rss=","-p",toString pid]}
  check (result.exitCode == 0) "RSS process query failed"
  let some value := result.stdout.trimAscii.toString.toNat? | throw (IO.userError "invalid RSS value")
  return value

def load (project : System.FilePath) : IO (Array OwnerPalette.Descriptor × Json) := do
  let source ← PageMap.pin project
  let mut found : Option (PageMap.Snapshot × System.FilePath) := none
  for storage in [Sidecar.Storage.database,.user] do
    let path ← CanonicalSource.Cache.directory source storage
    let some ready ← CanonicalSource.Cache.open? source storage | continue
    let some snapshot ← CanonicalSource.Cache.preparedAt? source path ready.metadata | continue
    found := some (snapshot,path)
    break
  let some (snapshot,path) := found | throw (IO.userError "existing checked canonical preparation required")
  let documents ← Persistence.Store.searchDocuments source
  let descriptors ← documents.toArray.mapM fun document => do
    let original ← Persistence.Store.readLocatedOutcome source (← Persistence.Store.locateOutcome source document.owner)
    let owner := Persistence.selectionKey original.relation
    let ready ← PreparedSourceView.readOwner snapshot source.head.identity owner
    return ready.stored.descriptor
  check (!descriptors.isEmpty) "checked recipe metadata is empty"
  return (descriptors,Json.mkObj [("project",toJson project.toString),("head",toJson source.head),
    ("recipes",toJson path.toString),("recipeHead",toJson snapshot.head),
    ("owners",toJson descriptors.size),("metadataRows",toJson (descriptors.foldl (fun n d => n+d.rows.size) 0)),
    ("origins",toJson (descriptors.foldl (fun n d => n+d.rows.foldl (fun n row => n+row.origins.size) 0) 0))])

def run (mode : String) (project destination : System.FilePath) (count : Nat) : IO Unit := do
  check ((mode == "rebuild" || mode == "reuse") && count == 80 && !(← destination.pathExists)) "fresh declared component trial required"
  IO.FS.createDirAll destination
  let (descriptors,input) ← load project
  let started ← IO.monoNanosNow
  let some expected := prepare descriptors | throw (IO.userError "original descriptor expansion failed")
  let preparationNs := (← IO.monoNanosNow)-started
  let before ← ownRss
  let begin ← IO.monoMsNow
  let mut tasks := #[]
  for ticket in [:count] do
    tasks := tasks.push (← IO.asTask (do
      if mode == "rebuild" then
        let some result := rebuild ticket descriptors | throw (IO.userError "repeated descriptor expansion failed")
        return result
      else return reuse ticket expected) .dedicated)
  let mut held := #[]
  for task in tasks do held := held.push (← IO.ofExcept task.get)
  let elapsedMs := (← IO.monoMsNow)-begin
  let retainedRss ← ownRss
  save (destination/"held.json") (Json.mkObj [("clients",toJson held.size),
    ("metadataReadsEach",toJson expected.rows.size),("beforeRssKiB",toJson before),
    ("retainedRssKiB",toJson retainedRss),("elapsedMs",toJson elapsedMs)])
  IO.sleep 500
  for (result,ticket) in held.zipIdx do
    check (result.ticket == ticket && result.ready.rows == expected.rows) "cached metadata changed contents or order"
    for read in expected.rows do
      check (result.ready.bindings.lookup (bindingKey read) == expected.bindings.lookup (bindingKey read))
        "cached binding directory changed duplicates or ordering"
    for owner in (expected.rows.map ownerKey).toList.eraseDups do
      check (result.ready.owners.lookup owner == expected.owners.lookup owner)
        "cached owner directory changed duplicates or ordering"
  save (destination/"result.json") (Json.mkObj [("mode",toJson mode),("input",input),
    ("clients",toJson held.size),("metadataReadsEach",toJson expected.rows.size),
    ("preparationNs",toJson preparationNs),("elapsedMs",toJson elapsedMs),
    ("beforeRssKiB",toJson before),("retainedRssKiB",toJson retainedRss),
    ("allValuesAndLookupsEqual",toJson true),("fullHookTrial",toJson false),
    ("sharedReadyIsQueryIndependent",toJson true),("adopted",toJson false)])

end PreparedReadControls

#print axioms PreparedReadControls.prepared_rows
#print axioms PreparedReadControls.prepared_binding_lookup
#print axioms PreparedReadControls.prepared_owner_lookup

def main (args : List String) : IO Unit := do
  let [mode,project,destination] := args | throw (IO.userError "rebuild|reuse PROJECT DESTINATION")
  PreparedReadControls.run mode (.mk project) (.mk destination) 80
