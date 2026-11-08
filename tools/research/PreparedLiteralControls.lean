import tools.research.ScorePrepareControls
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses

run_elab do
  let environment ← getEnv
  for (consumer,dependency) in [
      (``PreparedFocusFacts.compile,``QueryLiterals.identifiers),
      (``SharedReadViews.View.project,``PreparedFocusFacts.Stored.literalData),
      (``Transport.build,``Research.PreparedLiteralFocus.Data.matches),
      (``prepareAutomatic,``literalFocusWith)] do
    let some body := (environment.find? consumer).bind (·.value?) | throwError "Missing literal fact consumer {consumer}"
    unless body.getUsedConstants.contains dependency do throwError "Disconnected literal fact edge {consumer} -> {dependency}"
  let some body := (environment.find? ``Research.PreparedLiteralFocus.focusWords).bind (·.value?) |
    throwError "Missing prepared literal loop"
  if body.getUsedConstants.contains ``QueryLiterals.identifiers then throwError "Prepared literal loop still parses original text"

#print axioms literalFocusWith_compiled
#print axioms PreparedFocusFacts.compiled_literal_focus_exact
#print axioms Research.PreparedLiteralFocus.Data.foreign_work_rejected

namespace Eggshell.Research.PreparedLiteralControls
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh literal publication controls required"
  IO.FS.createDirAll root
  let works : List Value := [.text "",.text "inspect OPT_x --target 日本語",
    .applyList .all [(.semantic,.text "structured work")],.atom ⟨#[255]⟩]
  let outputs : List Value := [.text "",.text "OPT_x Lang_HLSL OPT_fsyntax_only 커널 café",
    .text "{\"resource\":\"mcp://ticket/42\",\"text\":\"OPT_x\",\"tail\":\"END\"}",.applyList .all []]
  let questions := ["", "plain prose", "-x", "--target -fsyntax-only", "-42 --- list-marker", "-x -x -Ｆｏｏ"]
  let mut owners : Array (OutcomeEdge × PreparedFocusFacts.Stored) := #[]
  let mut controls := 0
  for work in works do
    for outcome in outputs do
      let owner := OutcomeEdge.make work outcome [] (by simp) (by simp [maxOutcomeObservations])
      let stored := PreparedFocusFacts.compile (Persistence.selectionKey owner.relation) (Persistence.selectionKey work)
        ((Persistence.Store.text? work).getD "") ((Persistence.Store.text? outcome).getD "")
      let restored : PreparedFocusFacts.Stored ← IO.ofExcept (fromJson? (toJson stored))
      let ready ← IO.ofExcept (PreparedFocusFacts.check stored.owner restored)
      let facts := ready.stored.literalData
      check (facts.matches stored.owner stored.work stored.originalWindows) "prepared domain mismatch"
      check (!(facts.matches "foreign-owner" stored.work stored.originalWindows) &&
        !(facts.matches stored.owner "foreign-work" stored.originalWindows) &&
        !(facts.matches stored.owner stored.work ("foreign-window"::stored.originalWindows))) "foreign literal domain admitted"
      for question in questions do
        for ranked in [[],[0],[99,0,1,0],(List.range stored.originalWindows.length).reverse] do
          let expected := QueryLiterals.focus question (evidenceSearchWindows owner) ranked
          let actual := literalFocusWith (some facts) question owner ranked
          let unchanged := literalFocusWith none question owner ranked
          check (actual.windows == expected.windows && actual.anchors == expected.anchors &&
            unchanged.windows == expected.windows && unchanged.anchors == expected.anchors)
            "published literal facts changed original windows or anchors"
          controls := controls+1
      owners := owners.push (owner,stored)
  let database ← DB.PageMap.create (root/"facts.egg") "literal-publication-control"
  discard <| DB.PageMap.withWriter database fun writer => do
    for (_,stored) in owners do
      PreparedSourceView.publishOwner writer stored.owner ⟨#[],[]⟩ (some stored)
  let snapshot ← DB.PageMap.pin database.directory
  for (_,stored) in owners do
    let ready ← PreparedSourceView.readOwner snapshot snapshot.head.identity stored.owner
    let some facts := ready.focus | throw (IO.userError "persisted literal facts missing")
    check (facts.stored.literalData == stored.literalData) "durable original literal metadata changed"
  IO.FS.writeFile (root/"result.json") (Json.mkObj [("controls",toJson controls),("storedOwners",toJson owners.size),
    ("durableMetadataRoundTrip",toJson true),("foreignDomainsRejected",toJson true),
    ("allOriginalWindowsAndAnchorsExact",toJson true),("actualConsumerDeclarationsChecked",toJson true),
    ("providerCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.PreparedLiteralControls

def main (args : List String) : IO UInt32 := do
  match args with
  | ["prepared-literal-controls",root] => Eggshell.Research.PreparedLiteralControls.run (.mk root); return 0
  | ["freeze",_] | ["probe",_] => scopedEncodeDeliveryMain args; return 0
  | _ => preparedLiteralsParentMain args
