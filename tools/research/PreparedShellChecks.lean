module
public import Eggshell.CanonicalSourceCache
public import tools.research.PreparedShellOrdering
@[expose] public section

namespace Eggshell.Research.PreparedShellChecks
open Lean Synapses CanonicalSource

def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
structure Input where
  shells : Array PreparedPlanMetadata.Shell
  orders : PreparedShellOrdering.Orders
structure Result where
  shell : PreparedPlanMetadata.Shell
  locators : String
  combineMs : Nat
  locatorMs : Nat

@[noinline,nospecialize] def originalCombine (shells : Array PreparedPlanMetadata.Shell) :=
  PreparedPlanMetadata.combine shells
@[noinline,nospecialize] def originalLocators (shell : PreparedPlanMetadata.Shell) :=
  PreparedPlanMetadata.locators shell

def timed (input : IO.Ref Input) (prepared : Bool) : IO Result := do
  let input ← input.get
  let began ← IO.monoMsNow
  let shell ← (← IO.mkRef (if prepared then PreparedShellOrdering.combine input.orders input.shells
    else originalCombine input.shells)).get
  let combined ← IO.monoMsNow
  let locators ← (← IO.mkRef (if prepared then PreparedShellOrdering.locators input.orders shell
    else originalLocators shell)).get
  return ⟨shell,locators,combined-began,(← IO.monoMsNow)-combined⟩

def run (database output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve preceding metadata-order observation"
  let source ← DB.PageMap.pin database
  let some manifest ← Cache.open? source .user | throw (IO.userError "prepared project view is absent")
  let directory ← Cache.directory source .user
  let some index ← Cache.preparedAt? source directory manifest.metadata |
    throw (IO.userError "prepared project view is not pinned")
  let input ← index.foldRange ⟨"view-document:","view-document;"⟩ (fun input row => do
    let some id := (row.1.drop "view-document:".length).toString.toNat? | return input
    let state ← index.readPayload (Cache.stateName id) >>= Cache.decode (α := Cache.OwnerState)
    let ready ← PreparedSourceView.readOwner index source.head.identity state.owner
    let some shell := PreparedPlanMetadata.describe state.owner ready.stored.descriptor |
      throw (IO.userError "original descriptor has no shell")
    let mut orders := input.orders
    for file in ready.stored.descriptor.files do
      if !orders.contains file then orders := orders.insert file (PreparedSourceView.fileReady file)
    return {shells := input.shells.push shell,orders}) (⟨#[],{}⟩ : Input)
  check (input.shells.size == 40 && !input.orders.isEmpty) "all actual original owner headers required"
  let some (first,_) := input.orders.toArray[0]? | throw (IO.userError "original file header disappeared")
  let other := {first with relative := "別名/café/커널/資料.json"}
  let mismatch := ({} : PreparedShellOrdering.Orders).insert first (PreparedSourceView.fileReady other)
  let examples := #[#[],input.shells.extract 0 1,input.shells.extract 0 8,input.shells,
    input.shells.reverse,input.shells++input.shells]
  let mut controls := 0
  for shells in examples do
    for orders in #[input.orders,{},mismatch] do
      let expected := originalCombine shells
      let actual := PreparedShellOrdering.combine orders shells
      check (expected == actual && originalLocators expected == PreparedShellOrdering.locators orders actual)
        "combined keys, owner order or rendered locations changed"
      controls := controls+1
  let arguments ← IO.mkRef input
  let mut rows := #[]
  for repetition in [:3] do
    let order := if repetition%2 == 0 then #[false,true] else #[true,false]
    let a ← timed arguments order[0]!
    let b ← timed arguments order[1]!
    check (a.shell == b.shell && a.locators == b.locators) "complete metadata-order comparison changed output"
    let before := if order[0]! then b else a
    let after := if order[0]! then a else b
    rows := rows.push (Json.mkObj [("repetition",toJson repetition),("preparedFirst",toJson order[0]!),
      ("originalCombineMs",toJson before.combineMs),("preparedCombineMs",toJson after.combineMs),
      ("originalLocatorMs",toJson before.locatorMs),("preparedLocatorMs",toJson after.locatorMs),
      ("keys",toJson a.shell.keys.size),("ownerOrder",toJson a.shell.owners),
      ("locatorsSha256",toJson (Sha256.hex a.locators.toUTF8)),("fullOutputEqual",toJson true)])
  let after ← DB.PageMap.pin database
  check (source.head == after.head) "metadata observation changed the project publication"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("metadata",toJson manifest.metadata),
    ("owners",toJson input.shells.size),("distinctFiles",toJson input.orders.size),("controls",toJson controls),
    ("rows",toJson rows),("originalHeadUnchanged",toJson true),
    ("scope",toJson "all persisted owner descriptors; component observation, not replay of request-specific families or full hook latency"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.PreparedShellChecks
def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "metadata order DATABASE OUTPUT")
  Eggshell.Research.PreparedShellChecks.run (.mk database) (.mk output)
