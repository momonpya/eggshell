import Eggshell.SearchProvider
import Eggshell.SemanticMatcher
import Eggshell.Handoff
import tools.WindowRanks

open Eggshell

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let document : Persistence.Store.SearchDocument := {
    owner := 0
    work := 0
    windows := (List.range 65).map toString }
  require (SemanticMatcher.WindowPull.check? document (List.range 33)).isNone
    "repair requests must still reject more than 32 windows"
  let some ranked := WindowRanks.Choices.check? 65 (List.range 65).reverse |
    throw (IO.userError "a complete original window order was rejected")
  require (ranked.handles.map Fin.val == (List.range 65).reverse) "rank order changed"
  require (WindowRanks.Choices.check? 65 [0, 0]).isNone "duplicate rank accepted"
  require (WindowRanks.Choices.check? 65 [65]).isNone "foreign rank accepted"
  require (WindowRanks.Choices.check? 0 []).isSome "empty domain rejected"
  require (WindowRanks.Choices.check? 100000 (List.range 100000).reverse).isSome
    "large source-domain hints must use linear distinctness validation"
  let order : SemanticMatcher.WindowChoice := ⟨0, (List.range 65).reverse⟩
  require (SemanticMatcher.completeWindowOrders [document] [order]) "complete source order rejected"
  require (!SemanticMatcher.completeWindowOrders [document] [⟨0, [0, 0]⟩]) "repeated order accepted"
  require (!SemanticMatcher.completeWindowOrders [document] [⟨0, [0]⟩]) "omitted order accepted"
  require (!SemanticMatcher.completeWindowOrders [document] [⟨1, (List.range 65)⟩]) "foreign order accepted"
  let rows := (List.range 65).foldl (fun state index =>
    SearchProvider.WindowScore.add state index.toFloat index) {}
  require (rows.positions.length == 65) "scoring discarded a computed position"
  let ordered := (rows.positions.mergeSort SearchRank.scoreOrder).map Prod.snd
  require (ordered == (List.range 65).reverse) "full numerical order changed"
  require (rows.best == some 64.0) "document score changed"
  let windows := (List.range 65).map fun index => if index == 20 then "common rare" else "common"
  let early := Plugin.focusedEvidenceWindows "common rare" windows (List.range 16)
  let complete := Plugin.focusedEvidenceWindows "common rare" windows (List.range 65)
  require (!early.contains 20 && complete.contains 20 && complete.length == 16)
    "lexical evidence beyond the early numerical cutoff must return without increasing the cue budget"
  IO.println "window ranks: original-domain order checked; repair requests remain bounded to 32"
