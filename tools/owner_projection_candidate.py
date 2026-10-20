"""Compile both checked owner projections through the proved array builder."""
from context_candidate import once

TARGETS = '''
lean_lib OwnerProjectionResearch where
  roots := #[`tools.OwnerProjection]

lean_exe owner_projection_tests where
  root := `tools.OwnerProjectionTests
'''
HELPERS = ['OwnerProjection.lean', 'OwnerProjectionTests.lean']

RESOLVE = '''def IndexedSemanticNominations.fromProjection (result : OwnerProjection.Result Nat Value) :
    IndexedSemanticNominations := {
  durable := result.durable, staged := result.staged
  durableWindows := result.durableWindows, stagedWindows := result.stagedWindows
  durableRanking := result.durableRanking, stagedRanking := result.stagedRanking
  presentationOrder := result.presentationOrder, focused := result.focused }

def IndexedSemanticNominations.toProjection (result : IndexedSemanticNominations) :
    OwnerProjection.Result Nat Value := {
  durable := result.durable, staged := result.staged
  durableWindows := result.durableWindows, stagedWindows := result.stagedWindows
  durableRanking := result.durableRanking, stagedRanking := result.stagedRanking
  presentationOrder := result.presentationOrder, focused := result.focused }

theorem IndexedSemanticNominations.projection_roundtrip (result : IndexedSemanticNominations) :
    fromProjection (toProjection result) = result := by cases result; rfl

theorem IndexedSemanticNominations.projection_preserved (result : OwnerProjection.Result Nat Value) :
    toProjection (fromProjection result) = result := by cases result; rfl

/-- Resolve the same checked request document through its closed source
array. The accumulator cannot make a foreign source or window authoritative. -/
def resolveSemanticOwner {σ : Type} (owner : σ → Sum Nat Value) (table : Array σ)
    (missing : String) {documents : List Persistence.Store.SearchDocument}
    (nomination : SemanticMatcher.IndexedNomination documents) :
    IO (OwnerProjection.Choice Nat Value) := do
  let some source := table[nomination.document.owner]? | throw (IO.userError missing)
  pure (owner source, nomination.indices)

'''


def handoff(source):
    source = once(source, 'public import Eggshell.SemanticMatcher\n',
        'public import Eggshell.SemanticMatcher\npublic import tools.OwnerProjection\n')
    declaration = source.index('def indexedSemanticNominationsUsing (snapshot')
    comment = source.rfind('/--', 0, declaration)
    source = source[:comment] + RESOLVE + source[comment:]
    for name, end_name, datatype, table, result, related_error, ranked_error in [
            ('indexedSemanticNominationsUsing', 'semanticChildIds', 'IndexedSemanticSource',
                'sourceTable', 'indices', 'foreign staged semantic nomination', 'foreign ranked semantic source'),
            ('federatedSemanticNominations', 'federatedDiscovery', 'FederatedSemanticSource sources',
                'table', 'nominated', 'foreign federated semantic nomination', 'foreign federated ranked semantic source')]:
        start = source.index('def ' + name)
        stop = source.index('\ndef ' + end_name, start)
        body = source[start:stop]
        projection = body.index('  let mut found : IndexedSemanticNominations := {}')
        if not body.rstrip().endswith('pure (some found)'):
            raise ValueError('The checked owner projection boundary changed')
        body = body[:projection] + f'''  let owner : {datatype} → Sum Nat Value := fun source => match source with
    | .stored document => .inl document.owner
    | .staged candidate .. => .inr candidate.edge.relation
  (some ∘ IndexedSemanticNominations.fromProjection) <$>
    OwnerProjection.legacyIO {{}} {result}.related {result}.ranking
    (resolveSemanticOwner owner {table} "{related_error}")
    (resolveSemanticOwner owner {table} "{ranked_error}")
'''
        source = source[:start] + body + source[stop:]
    return source


def audit(source):
    source = once(source, '  for theoremName in #[', '''  for theoremName in #[``Eggshell.OwnerProjection.hasKey_exact,
      ``Eggshell.OwnerProjection.Windows.ranked_exact, ``Eggshell.OwnerProjection.project_exact,
      ``Eggshell.OwnerProjection.foldlM_view, ``Eggshell.OwnerProjection.projectM_exact,
      ``Eggshell.OwnerProjection.legacyM_exact, ``Eggshell.OwnerProjection.legacy_io_compiled,
      ``Eggshell.Plugin.IndexedSemanticNominations.projection_roundtrip,
      ``Eggshell.Plugin.IndexedSemanticNominations.projection_preserved,''')
    return source + '''
run_meta do
  let environment ← getEnv
  for caller in #[``Eggshell.Plugin.indexedSemanticNominationsUsing,
      ``Eggshell.Plugin.federatedSemanticNominations] do
    let some declaration := environment.find? caller | throwError "Missing owner projection caller"
    let some body := declaration.value? | throwError "Missing owner projection body"
    unless body.getUsedConstants.contains ``Eggshell.OwnerProjection.legacyIO &&
        body.getUsedConstants.contains ``Eggshell.Plugin.resolveSemanticOwner do
      throwError "Owner projection bypasses its checked source array or compiler equality"
'''


SOURCES = {'Eggshell/Handoff.lean': handoff, 'Eggshell/ContractAudit.lean': audit}
