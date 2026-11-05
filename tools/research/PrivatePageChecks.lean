import Eggshell.DB.PageMap
open Lean Eggshell.DB.PageMap
namespace Eggshell.Research.PrivatePageChecks
#print axioms LocalPages.encoded_bytes_bounded
#print axioms LocalPages.slots_bounded
#print axioms LocalPages.different_key_rejected
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def page : CachedPage :=
  ⟨⟨0,65536,"checksum","key","key",0,1⟩,⟨.leaf [("key",none)],by decide⟩⟩
def key (index : Nat) : SharedPageKey := ("scope","database","incarnation","authority",index)
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve prior private-page evidence"
  IO.FS.createDirAll root
  let backing ← PagePool.new
  backing.insert (key 0) page
  let left ← backing.forkPrivate
  let right ← backing.forkPrivate
  check ((← left.find (key 0) page.ref).isSome) "first private borrower lost checked page"
  check ((← left.find (key 0) page.ref).isSome) "private hit lost checked page"
  check ((← right.find (key 0) page.ref).isSome) "independent private borrower lost checked page"
  let otherScope : SharedPageKey := ("foreign","database","incarnation","authority",0)
  check ((← left.find otherScope page.ref).isNone) "page escaped original scope"
  check ((← left.find (key 0) {page.ref with checksum := "different"}).isNone) "private page accepted another full descriptor"
  let shared ← backing.stats
  let a := (← left.stats).getObjValD "privateFront"
  let b := (← right.stats).getObjValD "privateFront"
  check ((shared.getObjValAs? Nat "hits").toOption == some 2 &&
    (a.getObjValAs? Nat "hits").toOption == some 1 && (b.getObjValAs? Nat "hits").toOption == some 0)
    "private read updated a peer or repeated the shared-table hit"
  let mut pressure := LocalPages.State.empty
  for index in [:513] do
    pressure := pressure.insert (key index) page
    check (pressure.bytes ≤ LocalPages.maxBytes && pressure.entries.size ≤ LocalPages.maxEntries)
      "private reference pressure exceeded its allowance"
  check ((pressure.find (key 512) page.ref).isSome) "pressure eviction lost newest checked page"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [
    ("separateMutableFronts",toJson true),("oneSharedHitPerBorrower",toJson true),
    ("fullDescriptorAndScopeChecked",toJson true),("pressureInsertions",toJson (513 : Nat)),
    ("maxEncodedReferencedBytes",toJson LocalPages.maxBytes),("maxEntries",toJson LocalPages.maxEntries),
    ("left",a),("right",b),("shared",shared),("actualHookCapacityTested",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
end Eggshell.Research.PrivatePageChecks
