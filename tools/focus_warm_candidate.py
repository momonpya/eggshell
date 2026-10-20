"""Warm the complete source/focus input closure in an isolated checkout."""
from context_candidate import once, block


TARGETS = '''
lean_lib FocusResearch where
  roots := #[`tools.FocusWindows]

lean_exe focus_warm_tests where
  root := `tools.FocusWarmTests
'''

HELPERS = ['FocusWindows.lean', 'FocusWarmTests.lean']

INSPECTION = '''inductive InputState where
  | missing
  | invalid
  | valid (coverage : SearchProvider.EncodingCoverage)

structure WindowCoverage where
  windows : Nat := 0
  valid : Nat := 0
  missing : Nat := 0
  invalid : Nat := 0
  input : SearchProvider.InputTotals := {}
  deriving ToJson

def WindowCoverage.observe (counts : WindowCoverage) (state : InputState) : WindowCoverage :=
  let counts := {counts with windows := counts.windows + 1}
  match state with
  | .missing => {counts with missing := counts.missing + 1}
  | .invalid => {counts with invalid := counts.invalid + 1}
  | .valid coverage => {counts with valid := counts.valid + 1, input := counts.input.add coverage}

def inspectInput (options : SearchProvider.Options) (key : String) : IO InputState := do
  let paths := SearchProvider.vectorPaths options (SearchProvider.windowCacheKey options.model key)
  if ← paths.allM (fun path => return (← FileSystem.symlinkMetadata? path).isNone) then return .missing
  try
    let cached ← SearchProvider.indexedWindow options key
    pure (.valid cached.coverage)
  catch _ => pure .invalid

/-- Only prefixes intersecting Work need an original bounded read. The rest
reuse their original key and position. No whole Outcome is hydrated. -/
def planWindows (snapshot : DB.PageMap.Snapshot) : IO (List Window × List Window) := do
  let reader ← Persistence.Store.NodeReader.new snapshot
  let mut discovery : Array Window := #[]
  let mut focus : Array Window := #[]
  for document in ← Persistence.Store.searchDocuments snapshot do
    let work ← reader.read document.work
    let some text := Matcher.atomText? work | throw (IO.userError "warm Work is not indexed text")
    for (key, index) in document.windows.zipIdx do
      let original : Window := ⟨document, index, key, 0⟩
      discovery := discovery.push original
      let start := Plugin.evidenceWindowStart text.length index
      if start == 0 then focus := focus.push original else
        let originalText ← Persistence.Store.readSearchWindow snapshot document index
        let view := Plugin.evidenceWindowText text.length index originalText
        focus := focus.push ⟨document, index, Persistence.Store.windowKey view, start⟩
  pure (discovery.toList, focus.toList)

def viewCoverage (known : Std.HashMap String InputState) (windows : List Window) : IO WindowCoverage := do
  let mut seen : Std.HashSet String := {}
  let mut result : WindowCoverage := {}
  for window in windows do
    unless seen.contains window.key do
      seen := seen.insert window.key
      let some state := known[window.key]? | throw (IO.userError "warm input coverage lost a planned key")
      result := result.observe state
  pure result

/-- All original and focus-view keys are inspected once. Query vectors and
retired keys do not enter either live-view denominator. -/
def inspect (snapshot : DB.PageMap.Snapshot) (options : SearchProvider.Options) : IO Inspection := do
  let (discovery, focus) ← planWindows snapshot
  let mut known : Std.HashMap String InputState := {}
  let mut needed : Array Window := #[]
  let mut union : WindowCoverage := {}
  for window in discovery ++ focus do
    unless known.contains window.key do
      let state ← inspectInput options window.key
      known := known.insert window.key state
      union := union.observe state
      match state with
      | .valid _ => pure ()
      | _ => needed := needed.push window
  pure {
    coverage := {
      database := DB.Sidecar.Owner.ofSnapshot snapshot, revision := snapshot.head.revision
      model := options.model, windows := union.windows, valid := union.valid
      missing := union.missing, invalid := union.invalid, input := union.input
      encoderContract := SearchProvider.encoderContract, focusContract := Plugin.focusWindowContract
      discovery := ← viewCoverage known discovery, focus := ← viewCoverage known focus }
    needed := needed.toList }
'''


def handoff(source):
    source = once(source, 'public import Eggshell.PluginModel\n',
        'public import Eggshell.PluginModel\npublic import tools.FocusWindows\n')
    source = once(source, '''/-- A numerical view changes only the Work prefix of an existing window.
The original window slot remains the coordinate used by the graph renderer. -/
def evidenceWindowText (workChars index : Nat) (window : String) : String :=
  (window.drop (workChars + 1 - index * 384)).copy

''', '')
    return once(source, 'SemanticMatcher.nominateIndexed command question requests [] [] repair true receipt "focus"',
        'SemanticMatcher.nominateIndexed command question requests [] [] repair false receipt "focus"')


def warm(source):
    source = once(source, 'public import Eggshell.SearchProvider\n',
        'public import Eggshell.SearchProvider\npublic import tools.FocusWindows\n')
    source = once(source, '  encoderContract : String\n  deriving BEq, ToJson, FromJson',
        '  encoderContract : String\n  focusContract : String\n  deriving BEq, ToJson, FromJson')
    source = once(source, 'SearchProvider.encoderContract⟩',
        'SearchProvider.encoderContract, Plugin.focusWindowContract⟩')
    source = once(source, '    previous.encoderContract == current.encoderContract',
        '    previous.encoderContract == current.encoderContract && previous.focusContract == current.focusContract')
    source = once(source, 'old.encoderContract == value.encoderContract && old.revision > value.revision',
        'old.encoderContract == value.encoderContract && old.focusContract == value.focusContract && old.revision > value.revision')
    source = once(source, '  key : String\n\nstructure Coverage', '  key : String\n  start : Nat\n\n' +
        INSPECTION[:INSPECTION.index('def inspectInput')] + 'structure Coverage')
    source = once(source, '  input : SearchProvider.InputTotals\n  deriving ToJson',
        '  input : SearchProvider.InputTotals\n  focusContract : String\n  discovery : WindowCoverage\n  focus : WindowCoverage\n  deriving ToJson')
    source = block(source, '/-- Each live window key is counted once per owning DB.',
        'structure Result where', INSPECTION[INSPECTION.index('def inspectInput'):])
    source = once(source, '      encoderContract := SearchProvider.encoderContract, input := {}}',
        '      encoderContract := SearchProvider.encoderContract, input := {}\n' +
        '      focusContract := Plugin.focusWindowContract, discovery := {}, focus := {}}')
    return once(source, '''            let text ← Persistence.Store.readSearchWindow snapshot window.document window.index
            pure ({id := window.key, text} : SemanticMatcher.Item)''',
        '''            let original ← Persistence.Store.readSearchWindow snapshot window.document window.index
            let text := (original.drop window.start).copy
            unless Persistence.Store.windowKey text == window.key do
              throw (IO.userError "warm input disagrees with its pinned original suffix")
            pure ({id := window.key, text} : SemanticMatcher.Item)''')
