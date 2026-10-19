"""Explicit source overlay for a complete-context native research candidate.

Apply only to a copied checkout. No production source imports this module.
"""
import json


def once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('The context-candidate boundary changed: '+before[:70])
    return source.replace(before, after)


def block(source, start, stop, replacement):
    if source.count(start) != 1 or source.count(stop) != 1:
        raise ValueError('The context-candidate block changed: '+start)
    lo, hi = source.index(start), source.index(stop)
    return source[:lo]+replacement+'\n\n'+source[hi:]


COVERAGE = '''structure EncodingCoverage where
  characters : Nat
  visibleCharacters : Nat
  tokenizerMappedCharacters : Nat
  embeddedCharacters : Nat
  sourceTokens : Nat
  segments : Nat
  contextTokens : Nat
  overlapTokens : Nat
  completeTokenOffsets : Bool
  deriving ToJson, FromJson

def EncodingCoverage.valid (c : EncodingCoverage) : Bool :=
  c.characters ≤ 512 && c.embeddedCharacters == c.tokenizerMappedCharacters &&
  c.tokenizerMappedCharacters ≤ c.visibleCharacters && c.visibleCharacters ≤ c.characters &&
  0 < c.segments && c.segments ≤ 512 && 2 < c.contextTokens &&
  c.overlapTokens < c.contextTokens - 2 && c.sourceTokens ≤ c.segments * c.contextTokens &&
  c.completeTokenOffsets

/-- Counts window/reference positions, not unique whole-document characters. -/
structure InputTotals where
  windows : Nat := 0
  characters : Nat := 0
  visibleCharacters : Nat := 0
  tokenizerMappedCharacters : Nat := 0
  embeddedCharacters : Nat := 0
  vectors : Nat := 0
  tokens : Nat := 0
  deriving ToJson

def InputTotals.add (t : InputTotals) (c : EncodingCoverage) : InputTotals := {
  windows := t.windows + 1, characters := t.characters + c.characters
  visibleCharacters := t.visibleCharacters + c.visibleCharacters
  tokenizerMappedCharacters := t.tokenizerMappedCharacters + c.tokenizerMappedCharacters
  embeddedCharacters := t.embeddedCharacters + c.embeddedCharacters
  vectors := t.vectors + c.segments, tokens := t.tokens + c.sourceTokens }
'''

CHECKED = '''structure CheckedVector (cached : CachedVector) : Type where
  valid : Receipt.validId cached.window = true ∧
    cached.contract = encoderContract ∧ cached.coverage.valid = true ∧
    cached.vector.size = cached.coverage.segments ∧
    cached.vector.all packedFinite = true

def CheckedVector.make? (cached : CachedVector) : Option (CheckedVector cached) :=
  if valid : Receipt.validId cached.window = true ∧
      cached.contract = encoderContract ∧ cached.coverage.valid = true ∧
      cached.vector.size = cached.coverage.segments ∧ cached.vector.all packedFinite = true then
    some ⟨valid⟩ else none

theorem CheckedVector.source_shape (checked : CheckedVector cached) :
    ∃ encodings : Array String, cached.vector = encodings ∧ encodings.all packedFinite = true :=
  ⟨cached.vector, rfl, checked.valid.2.2.2.2⟩
'''

INDEXED = '''def indexedWindow (options : Options) (window : String) : IO CachedVector := do
  unless Receipt.validId window do throw (IO.userError "invalid indexed vector locator")
  for path in vectorPaths options (windowCacheKey options.model window) do
    try
      let cached ← loadVector path
      if cached.model == options.model && cached.window == window then return cached
    catch _ => pure ()
  throw (IO.userError "missing or unusable indexed embedding")

def indexedVectors (options : Options) (windows : List String) : IO Json := do
  let values ← windows.mapM fun window => do
    let cached ← indexedWindow options window
    observeInput options false cached.coverage
    pure (cached.vector.map Json.str)
  pure (.arr values.toArray.flatten)
'''


def provider(source):
    source = once(source, 'structure CacheProbes where', COVERAGE+'\nstructure CacheProbes where')
    source = once(source, '  scoredWindows : Nat := 0\n',
        '  scoredWindows : Nat := 0\n  sourceInput : InputTotals := {}\n  queryInput : InputTotals := {}\n')
    source = once(source, 'def number (json : Json)', '''def observeInput (options : Options) (query : Bool) (c : EncodingCoverage) : IO Unit := do
  let some sink := options.metrics | return
  sink.state.modify fun s => if query then {s with queryInput := s.queryInput.add c}
    else {s with sourceInput := s.sourceInput.add c}

def encoderContract : String := Sha256.hex MiniLM.embeddingSource.toUTF8

def number (json : Json)''')
    source = once(source, '  window : String\n  vector : Json\n',
        '  window : String\n  contract : String\n  coverage : EncodingCoverage\n  vector : Array String\n')
    source = block(source, 'structure CheckedVector (cached : CachedVector)',
                   'def cacheMatches (model text : String)', CHECKED)
    source = once(source, 'Sha256.hex model.toUTF8 ++ "-" ++ window',
        'Sha256.hex (model.toUTF8 ++ encoderContract.toUTF8) ++ "-" ++ window')
    source = once(source, 'def readVector (options : Options) (text : String) : IO (Option Json)',
        'def readCachedVector (options : Options) (text : String) : IO (Option CachedVector)')
    source = once(source, 'if cacheMatches options.model text cached then return some cached.vector',
        'if cacheMatches options.model text cached then return some cached')
    source = once(source, 'def saveVector (options : Options) (text : String) (vector : Json) : IO Unit := do',
        '''def readVector (options : Options) (text : String) : IO (Option Json) := do
  pure ((← readCachedVector options text).map (fun c => toJson c.vector))

def saveVector (options : Options) (text : String) (vector : Json)
    (coverage : EncodingCoverage) : IO Unit := do''')
    source = once(source, '''  let encoding ← IO.ofExcept (packVector vector)
  let cached : CachedVector := {
    model := options.model, window := Persistence.Store.windowKey text, vector := .str encoding}''',
        '''  unless coverage.characters == text.length do throw (IO.userError "embedding coverage source mismatch")
  let group ← IO.ofExcept vector.getArr?
  let encodings ← IO.ofExcept (group.mapM packVector)
  let cached : CachedVector := {
    model := options.model, window := Persistence.Store.windowKey text
    contract := encoderContract, coverage, vector := encodings}''')
    source = once(source, '    let available ← readVector options part\n',
        '    let available ← readCachedVector options part\n')
    source = once(source, '  for (text, vector) in missing.zip vectors.toList do saveVector options text vector',
        '''  let coverage ← IO.ofExcept (response.getObjValAs? (Array EncodingCoverage) "coverage")
  unless coverage.size == vectors.size do throw (IO.userError "embedding coverage count mismatch")
  for ((text, vector), measured) in (missing.zip vectors.toList).zip coverage.toList do
    saveVector options text vector measured''')
    source = once(source, '''    let some value ← readVector options part | throw (IO.userError "missing indexed embedding")
    pure value
  pure (.arr values.toArray)
''', '''    let some cached ← readCachedVector options part | throw (IO.userError "missing indexed embedding")
    observeInput options true cached.coverage
    pure (cached.vector.map Json.str)
  pure (.arr values.toArray.flatten)
''')
    source = block(source, 'def indexedVectors (options : Options)', 'abbrev RepairWindows', INDEXED)
    return source


def warm(source):
    source = once(source, '  candidates : Nat\n  deriving BEq, ToJson, FromJson',
        '  candidates : Nat\n  encoderContract : String\n  deriving BEq, ToJson, FromJson')
    source = once(source, '← Persistence.Store.getNat snapshot.get "candidates"⟩',
        '← Persistence.Store.getNat snapshot.get "candidates", SearchProvider.encoderContract⟩')
    source = once(source, 'previous.roots == current.roots && previous.candidates == current.candidates',
        'previous.roots == current.roots && previous.candidates == current.candidates &&\n    previous.encoderContract == current.encoderContract')
    source = once(source, '(old.database == value.database && old.provider == value.provider && old.revision > value.revision)',
        '(old.database == value.database && old.provider == value.provider &&\n        old.encoderContract == value.encoderContract && old.revision > value.revision)')
    source = once(source, '  invalid : Nat\n  deriving ToJson',
        '  invalid : Nat\n  encoderContract : String\n  input : SearchProvider.InputTotals\n  deriving ToJson')
    source = once(source, '  let mut invalid := 0\n',
        '  let mut invalid := 0\n  let mut input : SearchProvider.InputTotals := {}\n')
    source = once(source, '''        let usable ← try
          let _ ← SearchProvider.indexedVectors options [key]
          pure true
        catch _ => pure false
        if usable then valid := valid + 1''', '''        let usable ← try
          some <$> SearchProvider.indexedWindow options key
        catch _ => pure none
        if let some cached := usable then
          valid := valid + 1
          input := input.add cached.coverage''')
    source = once(source, 'model := options.model, windows := seen.size, valid, missing, invalid }',
        'model := options.model, windows := seen.size, valid, missing, invalid\n      encoderContract := SearchProvider.encoderContract, input }')
    return source


def numerical(source, context_source, inputs):
    source = once(source, 'encoder = None\n', 'encoder = None\nplanner = None\n')
    source = once(source, 'global encoder, lease', 'global encoder, lease, planner')
    source = once(source, '            from fastembed import TextEmbedding',
        '            verify_context_inputs()\n            from fastembed import TextEmbedding')
    source = once(source, 'threads=int(sys.argv[3]))',
        'threads=int(sys.argv[3]), local_files_only=True)\n            planner = Planner(encoder.model.tokenizer)')
    start = source.index('                for vector in active.embed(request["texts"]')
    stop = source.index('            finally:', start)
    source = source[:start]+'''                groups, coverage = encode_groups(active, request["texts"], planner)
                vectors = [[v.tolist() for v in group] for group in groups]
'''+source[stop:]
    source = once(source, 'result = {"vectors": vectors}', 'result = {"vectors": vectors, "coverage": coverage}')
    # The asset manifest is compiled into the provider, making the numerical
    # contract content-addressed rather than a manually numbered cache format.
    verify = '''
CONTEXT_INPUTS = json.loads(%s)
def verify_context_inputs():
    if sys.argv[1] != CONTEXT_INPUTS["model"]:
        raise ValueError("Model differs from the compiled encoder contract")
    for category, root in [("modelFiles", Path(sys.argv[2])), ("runtimeFiles", Path(sys.prefix))]:
        for relative, expected in CONTEXT_INPUTS[category].items():
            path = root / relative
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1048576), b""):
                    digest.update(chunk)
            if digest.hexdigest() != expected:
                raise ValueError("Encoder input differs from the compiled contract: "+relative)
''' % repr(json.dumps(inputs,sort_keys=True,separators=(',',':')))
    return context_source+'\n'+source.replace('if sys.argv[6:]',verify+'\nif sys.argv[6:]',1)


def readonly_test_fixture(source):
    # These existing tests exercise cache-owner retirement, with a deliberately
    # synthetic numerical vector. Adapt their input to the new required shape;
    # do not relax their filesystem assertions or claim actual model coverage.
    for text in ['owned private window','late private window']:
        original='SearchProvider.saveVector options "'+text+'" (.arr #[toJson (1 : Nat)])'
        visible=len(text.replace(' ',''))
        replacement='SearchProvider.saveVector options "'+text+'" (.arr #[.arr #[toJson (1 : Nat)]]) {\n'+\
            f'        characters := {len(text)}, visibleCharacters := {visible}\n'+\
            f'        tokenizerMappedCharacters := {visible}, embeddedCharacters := {visible}\n'+\
            '        sourceTokens := 1, segments := 1, contextTokens := 128, overlapTokens := 16\n'+\
            '        completeTokenOffsets := true }'
        source=once(source,original,replacement)
    return source


def main_test_fixture(source):
    if source.count('SearchProvider.saveVector')!=9:
        raise ValueError('Re-audit the synthetic main-suite vector fixtures')
    source=source.replace('SearchProvider.saveVector','saveFixtureVector')
    helpers='''def fixtureCoverage (text : String) : SearchProvider.EncodingCoverage :=
  let visible := (text.toList.filter (fun c => !c.isWhitespace)).length
  {characters := text.length, visibleCharacters := visible
   tokenizerMappedCharacters := visible, embeddedCharacters := visible
   sourceTokens := if text.isEmpty then 0 else 1
   segments := 1, contextTokens := 128, overlapTokens := 16, completeTokenOffsets := true}

/-- Synthetic vectors test batching/ownership, not actual encoder coverage. -/
def saveFixtureVector (options : SearchProvider.Options) (text : String)
    (vector : Lean.Json) : IO Unit :=
  SearchProvider.saveVector options text (.arr #[vector]) (fixtureCoverage text)

'''
    source=once(source,'def testIndexedNumericalWindows : IO Unit := do',
                helpers+'def testIndexedNumericalWindows : IO Unit := do')
    source=once(source,'''  IO.FS.writeFile bad ("{\\"model\\":\\"synthetic-cache-test-only\\",\\"window\\":\\"" ++
    Persistence.Store.windowKey "needle" ++ "\\",\\"vector\\":\\"000000000000f07f\\"}")''',
        '''  let nonfinite : SearchProvider.CachedVector := {
    model := base.model, window := Persistence.Store.windowKey "needle"
    contract := SearchProvider.encoderContract, coverage := fixtureCoverage "needle"
    vector := #["000000000000f07f"]}
  IO.FS.writeFile bad (Lean.toJson nonfinite).compress''')
    source=once(source,'''    model := base.model, window := Persistence.Store.windowKey "needle", vector := .str packed}''',
        '''    model := base.model, window := Persistence.Store.windowKey "needle"
    contract := SearchProvider.encoderContract, coverage := fixtureCoverage "needle", vector := #[packed]}''')
    source=once(source,'observed.vector == .str packed','observed.vector == #[packed]')
    return source
