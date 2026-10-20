"""Index complete ranking joins without changing any score or admission."""
from context_candidate import once

TARGETS = '''
lean_lib RankDirectoryResearch where
  roots := #[`tools.FirstIndex, `tools.OwnedRows]

lean_exe rank_directory_tests where
  root := `tools.RankDirectoryTests
'''
HELPERS = ['FirstIndex.lean', 'OwnedRows.lean', 'RankDirectoryTests.lean']


def rank(source):
    source = once(source, 'public import Eggshell.Frequency\n',
        'public import Eggshell.Frequency\npublic import tools.FirstIndex\n')
    source = once(source, '/-- All provider output goes through this constructor.', '''/-- Build each first-position directory once. Floating-point additions keep
their original ranking order, including duplicated ids within a ranking. -/
def fusedIndexed (rankings : List (List Nat)) : List Nat :=
  let directories := rankings.map fun ranking => firstTable Prod.fst ranking.zipIdx
  let ids := hashDistinct rankings.flatten
  let scores := ids.map fun id =>
    (directories.foldl (fun score directory =>
      match directory[id]? with
      | some (_, rank) => score + 1 / (61 + rank).toFloat
      | none => score) (0 : Float), id)
  (scores.mergeSort scoreOrder).map (·.2)

@[csimp] theorem fused_compiled : fused = fusedIndexed := by
  funext rankings
  simp only [fused, fusedIndexed, HashDistinct.reference, List.foldl_map,
    firstTable_exact]

/-- All provider output goes through this constructor.''')
    return once(source, 'theorem selected_no_duplicates', '''def selectIndexed (count limit : Nat) (anchors ranking : List Nat) : List Nat :=
  ((hashDistinct (anchors ++ ranking)).filter (· < count)).take limit

@[csimp] theorem select_compiled : select = selectIndexed := by
  funext count limit anchors ranking
  simp only [select, selectIndexed, HashDistinct.reference]

theorem selected_no_duplicates''')


def provider(source):
    source = once(source, 'theorem presentation_ranking_original', '''def presentationRankingIndexed (mode : String) (count : Nat) (semantic lexical : List Nat) : List Nat :=
  let combined := if mode == "lexical" then lexical
    else if mode == "semantic" then semantic
    else SearchRank.fused [semantic, lexical]
  (hashDistinct (combined ++ semantic ++ lexical ++ List.range count)).filter (· < count)

@[csimp] theorem presentation_ranking_compiled : presentationRanking = presentationRankingIndexed := by
  funext mode count semantic lexical
  simp only [presentationRanking, presentationRankingIndexed, HashDistinct.reference]

theorem presentation_ranking_original''')
    source = once(source, '/-- Candidate payloads never cross this protocol.', '''def indexedEvidenceWindows (evidence : List (Nat × List Nat))
    (ranked : List Nat) : List SemanticMatcher.WindowChoice :=
  ranked.filterMap fun index =>
    (evidence.find? (·.1 == index)).map fun row => ⟨row.1, row.2⟩

def indexedEvidenceWindowsUsing (evidence : List (Nat × List Nat))
    (ranked : List Nat) : List SemanticMatcher.WindowChoice :=
  let directory := FirstIndex.make Prod.fst evidence
  ranked.filterMap fun index => (directory.read index).map fun row => ⟨row.1, row.2⟩

@[csimp] theorem indexed_evidence_windows_compiled : indexedEvidenceWindows = indexedEvidenceWindowsUsing := by
  funext evidence ranked
  simp only [indexedEvidenceWindows, indexedEvidenceWindowsUsing, FirstIndex.read_exact]

/-- Candidate payloads never cross this protocol.''')
    return once(source, '''  let windows := ranked.filterMap fun index =>
    (evidence.find? (·.1 == index)).map fun row =>
      (⟨row.1, row.2⟩ : SemanticMatcher.WindowChoice)''',
        '  let windows := indexedEvidenceWindows evidence ranked')


def matcher(source):
    source = once(source, 'public import Eggshell.Paths\n',
        'public import Eggshell.Paths\npublic import tools.OwnedRows\n')
    position = source.index('def documentOwners (')
    additions = '''/-- Common original window validation; a directory cannot grant ownership
or accept an out-of-range, repeated or oversized window choice. -/
def resolveIndexedNomination (found : Option {row // row ∈ documents})
    (indices : List Nat) : Except String (Option (IndexedNomination documents)) := do
  let some document := found | return none
  if indices.isEmpty then
    return some ⟨document.val, document.property, [], by simp⟩
  let some pull := WindowPull.check? document.val indices |
    throw "semantic evidence window lies outside its document"
  return some ⟨document.val, document.property, pull.handles, pull.handles_bounded⟩

def indexedNominationsUsing (documents : List Persistence.Store.SearchDocument)
    (response : IndexedResponse) : Except String (List (IndexedNomination documents)) :=
  let directory := OwnedRows.make documents
  let choices := FirstIndex.make WindowChoice.document response.evidence
  (hashDistinct response.related).filterMapM fun index =>
    resolveIndexedNomination (directory.get index)
      ((choices.read index).map (·.indices) |>.getD [])

@[csimp] theorem indexed_nominations_compiled : indexedNominations = indexedNominationsUsing := by
  funext documents response
  unfold indexedNominationsUsing
  simp only [HashDistinct.reference, OwnedRows.get_exact, FirstIndex.read_exact]
  have same := append_fold_filterMapM
    (fun index => resolveIndexedNomination (OwnedRows.reference documents index)
      ((response.evidence.find? (·.document == index)).map (·.indices) |>.getD []))
    response.related.eraseDups []
  simp only [List.nil_append, bind_pure] at same
  rw [← same]
  clear same
  unfold indexedNominations
  congr 1
  funext nominations index
  have originalValue := OwnedRows.reference_value documents index
  cases original : OwnedRows.reference documents index with
  | none =>
      rw [original] at originalValue
      have missing : documents[index]? = none := by simpa using originalValue.symm
      unfold resolveIndexedNomination
      split
      · rfl
      · rename_i row present
        rw [missing] at present
        contradiction
  | some document =>
      rw [original] at originalValue
      have found : documents[index]? = some document.val := by simpa using originalValue.symm
      unfold resolveIndexedNomination
      split
      · rename_i missing
        rw [found] at missing
        contradiction
      · rename_i row present
        have same : row = document.val := Option.some.inj (present.symm.trans found)
        cases same
        dsimp only
        split
        · rfl
        · cases checked : WindowPull.check? document.val
            ((response.evidence.find? (·.document == index)).map (·.indices) |>.getD []) <;> rfl

'''
    return source[:position] + additions + source[position:]


def audit(source):
    source = once(source, '  for theoremName in #[', '''  for theoremName in #[``Eggshell.firstTable_exact,
      ``Eggshell.FirstIndex.read_exact, ``Eggshell.SearchRank.fused_compiled,
      ``Eggshell.SearchRank.select_compiled, ``Eggshell.SearchProvider.presentation_ranking_compiled,
      ``Eggshell.SearchProvider.indexed_evidence_windows_compiled,''')
    source = once(source, '  for theoremName in #[', '''  for theoremName in #[``Eggshell.OwnedRows.get_exact,
      ``Eggshell.OwnedRows.reference_value,
      ``Eggshell.append_fold_filterMapM, ``Eggshell.SemanticMatcher.indexed_nominations_compiled,''')
    return source + '''
run_meta do
  let environment ← getEnv
  let some declaration := environment.find? ``Eggshell.SearchProvider.handleIndexedUsing |
    throwError "Missing indexed numerical handler"
  let some body := declaration.value? | throwError "Numerical handler has no body"
  unless body.getUsedConstants.contains ``Eggshell.SearchProvider.indexedEvidenceWindows do
    throwError "Numerical ranking bypasses the exact evidence directory"
'''


SOURCES = {'Eggshell/SearchRank.lean': rank, 'Eggshell/SemanticMatcher.lean': matcher,
           'Eggshell/SearchProvider.lean': provider,
           'Eggshell/ContractAudit.lean': audit}
