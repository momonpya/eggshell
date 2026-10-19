"""Checked overlays for one dictionary-free retrieval policy and derived index."""
from context_candidate import once, block


def search_rank(source):
    source=once(source,'public import Eggshell.SearchUnicode\n',
        'public import Eggshell.SearchUnicode\npublic import Eggshell.HashDistinct\npublic import tools.RetrievalGrams\n')
    source=block(source,'@[extern "log1p"] opaque log1p','theorem deduplicated_nodup',
        '''def log1p (x : Float) : Float := RetrievalResearch.log1p x

def asciiTerm (c : Char) : Bool := RetrievalResearch.asciiTerm c

def rawTerms (text : String) : List String := RetrievalResearch.tokens text

def terms (text : String) : List String := hashDistinct (rawTerms text)''')
    source=once(source,'  deduplicated_nodup (rawTerms text)','  HashDistinct.nodup (rawTerms text)')
    source=block(source,'def anchor (term : String)','def scoreOrder',
        'def anchor (term : String) : Bool := RetrievalResearch.anchor term')
    source=block(source,'def rankRows (query : String)','def rankDocuments',
        '''def rankRows (query : String) (rows : List α) (contains : α → String → Bool)
    (frequency : String → Nat) (anchors : Bool) (population : Nat := rows.length) : List Nat :=
  RetrievalResearch.rankRows query rows contains frequency anchors population''')
    source=once(source,'simp only [rankRows, List.length_map, List.zipIdx_map, List.filterMap_map]',
        'simp only [rankRows, RetrievalResearch.rankRows, List.length_map, List.zipIdx_map, List.filterMap_map]')
    return source


def federated(source):
    source=once(source,'public import Eggshell.SemanticMatcher\n',
        'public import Eggshell.SemanticMatcher\npublic import tools.RetrievalIndex\n')
    source=once(source,'pure (← searchPosting snapshot unit).1',
        'pure (← RetrievalResearch.Index.strictPosting snapshot unit).1')
    extra='''def retrievalLookup (catalogue : Catalogue sources) (strict : Bool)
    (receipt : Option String) : IO (String → IO PostingSet) := do
  let lookups ← (List.finRange sources.size).mapM fun source => do
    let read ← if strict then RetrievalResearch.Index.strictLookup sources[source]
      else RetrievalResearch.Index.coarseLookup sources[source] receipt
    pure (source, read)
  pure fun unit => do
    let mut owners : PostingSet := {}
    for (source, read) in lookups do
      let (ids, _) ← read unit
      for id in ids do
        let canonical ← catalogue.identity.lookup source id
        unless catalogue.owners.contains canonical do
          throw (IO.userError "lexical posting names a foreign canonical owner")
        owners := owners.add canonical
    pure owners

'''
    source=once(source,'def frequency (catalogue : Catalogue sources)',extra+'def frequency (catalogue : Catalogue sources)')
    return source


def handoff(source):
    source=once(source,'public import Eggshell.SelectionAudit\n',
        'public import Eggshell.SelectionAudit\npublic import tools.RetrievalIndex\n')
    if source.count('Persistence.Store.searchPosting snapshot')!=2:
        raise ValueError('Re-audit direct lexical posting callers')
    source=once(source,'  let stagedSources := staged.map fun candidate =>',
        '  let lexicalPosting ← RetrievalResearch.Index.strictLookup snapshot\n  let stagedSources := staged.map fun candidate =>')
    source=once(source,'let (owners, count) ← Persistence.Store.searchPosting snapshot unit',
        'let (owners, count) ← lexicalPosting unit')
    source=once(source,'''    lexical := lexicalNominations population (Persistence.Store.searchPosting snapshot)
      (fun id => Persistence.Store.getNat snapshot.get (Persistence.Store.key "member" id))''',
        '''    lexical := fun current staged => do
      let posting ← RetrievalResearch.Index.coarseLookup snapshot receipt
      lexicalNominations population posting
        (fun id => Persistence.Store.getNat snapshot.get (Persistence.Store.key "member" id)) current staged''')
    source=once(source,'  let workIds := Std.HashSet.ofList (catalogue.documents.map (·.work))',
        '  let lexicalPosting ← Persistence.Store.Federated.retrievalLookup catalogue true receipt\n  let workIds := Std.HashSet.ofList (catalogue.documents.map (·.work))')
    source=once(source,'''    lexical := lexicalNominations catalogue.documents.length
      (fun unit => do
        let owners ← Persistence.Store.Federated.postings catalogue unit true
        pure (owners.toList, owners.size))
      (fun id => do
        let some order := catalogue.orders[id]? | throw (IO.userError "foreign federated lexical owner")
        pure order)''',
        '''    lexical := fun current staged => do
      let posting ← Persistence.Store.Federated.retrievalLookup catalogue false receipt
      lexicalNominations catalogue.documents.length
        (fun unit => do
          let owners ← posting unit
          pure (owners.toList, owners.size))
        (fun id => do
          let some order := catalogue.orders[id]? | throw (IO.userError "foreign federated lexical owner")
          pure order) current staged''')
    source=once(source,'let owners ← Persistence.Store.Federated.postings catalogue unit true',
        'let owners ← lexicalPosting unit')
    return source


def warm(source):
    source=once(source,'public import Eggshell.SearchProvider\n',
        'public import Eggshell.SearchProvider\npublic import tools.RetrievalIndex\n')
    source=once(source,'def required (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Bool := do',
        '''def lexicalOnly (command : List String) : Bool :=
  match command with
  | _ :: "search-provider" :: args =>
    match SearchProvider.parse {cache := .mk ".", models := .mk "."} args with
    | .ok options => options.mode == "lexical"
    | .error _ => false
  | _ => false

def required (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Bool := do
  unless ← RetrievalResearch.Index.ready snapshot do return true
  if lexicalOnly target.command then return false''')
    source=once(source,'  elapsedMs : Nat\n  deriving ToJson',
        '  elapsedMs : Nat\n  lexical : RetrievalResearch.Index.Result\n  deriving ToJson')
    source=once(source,'''  let started ← IO.monoMsNow
  let settings ← options snapshot target.command target.storage''',
        '''  let started ← IO.monoMsNow
  let lexical ← RetrievalResearch.Index.warm snapshot target.storage
  if lexicalOnly target.command then
    let empty : Coverage := {
      database := DB.Sidecar.Owner.ofSnapshot snapshot
      revision := snapshot.head.revision, model := "lexical-only", windows := 0
      valid := 0, missing := 0, invalid := 0}
    return ⟨empty, empty, 0, 0, (← IO.monoMsNow) - started, lexical⟩
  let settings ← options snapshot target.command target.storage''')
    source=once(source,'return ⟨before.coverage, before.coverage, 0, 0, (← IO.monoMsNow) - started⟩',
        'return ⟨before.coverage, before.coverage, 0, 0, (← IO.monoMsNow) - started, lexical⟩')
    source=once(source,'pure ⟨before.coverage, after.coverage, current.needed.length, batches, (← IO.monoMsNow) - started⟩',
        'pure ⟨before.coverage, after.coverage, current.needed.length, batches, (← IO.monoMsNow) - started, lexical⟩')
    return source


def worker(source):
    source=once(source,'''  let pinned ← target.owner.pin
  let directory ← target.indexes pinned''',
        '''  let pinned ← target.owner.pin
  let _ ← RetrievalResearch.Index.warm pinned target.storage
  let directory ← target.indexes pinned''')
    source=once(source,'''            if let some command := pending.semanticMatcher then
              -- Persist the ticket before consuming the replayable save job.
              -- The writer never waits for model initialization or encoding.
              queueIndex target command promotion''',
        '''            let command := pending.semanticMatcher.getD
              [(← IO.appPath).toString, "search-provider", "--mode", "lexical"]
            -- Lexical maintenance also survives a saving chat without an encoder.
            queueIndex target command promotion''')
    return source


def cli(source):
    source=once(source,'''    let some command := command |
      return Json.mkObj (fields ++ [("state", toJson "provider-unavailable")])''',
        '''    let fields := fields ++ [("lexical", ← RetrievalResearch.Index.status snapshot)]
    let lexicalReady ← RetrievalResearch.Index.ready snapshot
    let some command := command |
      return Json.mkObj (fields ++ [("state", toJson (if lexicalReady then "warm" else "cold")),
        ("numerical", toJson "disabled")])''')
    source=once(source,'    let options ← Warm.options snapshot command',
        '''    if Warm.lexicalOnly command then
      return Json.mkObj (fields ++ [("state", toJson (if lexicalReady then "warm" else "cold")),
        ("numerical", toJson "disabled")])
    let options ← Warm.options snapshot command''')
    source=once(source,'''    let state := if inspected.coverage.invalid > 0 then "invalid"
      else if inspected.coverage.missing > 0 then "cold" else "warm"''',
        '''    let state := if inspected.coverage.invalid > 0 then "invalid"
      else if inspected.coverage.missing > 0 || !lexicalReady then "cold" else "warm"''')
    source=once(source,'''  let some command := command |
    throw (IO.userError "numerical provider is disabled or not installed")''',
        '''  let command := command.getD [(← IO.appPath).toString, "search-provider", "--mode", "lexical"]''')
    return source


TRANSFORMS={'Eggshell/SearchRank.lean':search_rank,'Eggshell/FederatedSearch.lean':federated,
            'Eggshell/Handoff.lean':handoff,'Eggshell/Warm.lean':warm,
            'Eggshell/Worker.lean':worker,'Eggshell/PluginCli.lean':cli}


WARM_FIXTURE = '''/-- Explicit preparation for ordinary warm-DB semantic fixtures. Native
cold/timeout/worker tests call the actual runtime without this test wrapper. -/
def warmHandoff (selection : Config.Selection) (current : String)
    (deliveredGraphs : List String) (enforce : Bool)
    (evidenceText : Option String := none)
    (staged : List Value := []) (stagedVisible : Bool := true)
    (enableLocalUnion : Bool := true)
    (sourceContext : Option SourceContext := none)
    (publishMemo : Bool := true) : IO (Option Handoff) := do
  if selection.semanticMatcher.isSome then
    for egg in selection.read do
      if let some snapshot ← DB.PageMap.open? egg.path then
        let storage := if selection.write.any (·.path.normalize == egg.path.normalize)
          then DB.Sidecar.Storage.database else .user
        let _ ← RetrievalResearch.Index.warm snapshot storage
        pure ()
  Plugin.automaticHandoff selection current deliveredGraphs enforce evidenceText
    staged stagedVisible enableLocalUnion sourceContext publishMemo

'''


def main_fixture(source):
    if 'warmHandoff' in source:
        raise ValueError('Fixture was already adapted')
    source=source.replace('automaticHandoff ', 'warmHandoff ')
    source=once(source,'def check (condition : Bool)',WARM_FIXTURE+'def check (condition : Bool)')
    source=once(source,'  for session in ["db-cache-chat-one", "db-cache-chat-two"] do',
        '''  let _ ← RetrievalResearch.Index.warm (← DB.PageMap.pin leftPath) .database
  for session in ["db-cache-chat-one", "db-cache-chat-two"] do''')
    return source


def page_fixture(source):
    if 'warmHandoff' in source:
        raise ValueError('Fixture was already adapted')
    source=source.replace('automaticHandoff ', 'warmHandoff ')
    source=once(source,'def require (accepted : Bool)',WARM_FIXTURE+'def require (accepted : Bool)')
    source=once(source,'    let nominationSource ← PageMap.pin largePath',
        '''    let _ ← RetrievalResearch.Index.warm (← PageMap.pin largePath) .database
    let nominationSource ← PageMap.pin largePath''')
    return source


def deadline_fixture(source):
    source=once(source,'    for rows in [original, original.reverse, original.drop 1, original ++ original] do',
        '''    let original := original.map (fun terms => SearchRank.terms (String.intercalate " " terms))
    for rows in [original, original.reverse, original.drop 1, original ++ original] do''')
    source=once(source,'  let rows := [["rare"]] ++ List.replicate 4 ["common_a", "common_b"] ++ List.replicate 95 []',
        '''  let _ ← RetrievalResearch.Index.warm (← DB.PageMap.pin database) .database
  let rows := ([["rare"]] ++ List.replicate 4 ["common_a", "common_b"] ++ List.replicate 95 []).map
    (fun terms => SearchRank.terms (String.intercalate " " terms))''')
    return source


FIXTURES={'TestMain.lean':main_fixture,'tests/PageDBTests.lean':page_fixture,
          'tests/SemanticDeadlineTests.lean':deadline_fixture}
