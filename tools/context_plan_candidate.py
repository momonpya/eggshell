"""Materialize exact context preparation before trying budget alternatives."""
from context_candidate import once


TARGETS = '''
lean_lib ContextPlanResearch where
  roots := #[`tools.BudgetPlan]

lean_exe context_plan_tests where
  root := `tools.ContextPlanTests
'''
HELPERS = ['BudgetPlan.lean', 'ContextPlanTests.lean']


PROOFS = '''theorem prepareContextualOwnerPlan_exact (delivered : List String) (windows : List Nat)
    (owner : OutcomeEdge) (connections : String) (sources : List SourceEvidence.Record)
    (slice : TransportSlice) :
    (prepareContextualOwnerPlan delivered windows owner connections sources slice).eval =
      prepareContextualOwnerPart delivered windows owner connections sources slice := by
  funext budget
  cases outcome : Matcher.atomText? owner.outcome <;>
    cases work : Matcher.atomText? owner.work <;>
    simp only [prepareContextualOwnerPlan, prepareContextualOwnerPart, outcome, work]
  all_goals split <;> try rfl
  all_goals split <;> rfl

@[noinline] def prepareContextualSlicePlan (delivered : List String) (windows : List Nat)
    (slice : TransportSlice) : BudgetPlan TransportSlice :=
  match slice.members with
  | [] => .constant none
  | first :: _ =>
    let selected := slice.members.filter (·.matched.retrieved)
    if windows.isEmpty || selected.isEmpty then .constant (some slice) else
      let owner := first.matched.edge
      let connections := "\\n".intercalate ((selected.map fun item =>
        "  PRIOR OUTCOME " ++ displayKey item.matched.projectedEdge.relation ++
          " -> EVIDENCE " ++ displayKey owner.outcome).eraseDups)
      let original := {slice with members := selected, visibleKeys := (selected.map graphKey).eraseDups}
      (prepareContextualOwnerPlan delivered windows owner connections first.sources original).map fun data =>
        {original with keys := data.keys, text := data.text, context := data.context}

theorem prepareContextualSlicePlan_exact (delivered : List String) (windows : List Nat)
    (slice : TransportSlice) :
    (prepareContextualSlicePlan delivered windows slice).eval = prepareContextualSlice delivered windows slice := by
  funext budget
  cases members : slice.members with
  | nil => simp [prepareContextualSlicePlan, prepareContextualSlice, members, BudgetPlan.eval]
  | cons first rest =>
    simp only [prepareContextualSlicePlan, prepareContextualSlice, members]
    split
    · rfl
    · rw [BudgetPlan.eval_map, prepareContextualOwnerPlan_exact]
      rfl

@[noinline] def prepareContextualSupportPlan (delivered : List String) (windows : List Nat)
    (support : SourceSupport roots all unions) : BudgetPlan TransportSlice :=
  let original := renderSourceSupport support
  (prepareContextualOwnerPlan delivered windows support.owner
    ("  SUPPORT OUTCOME " ++ displayKey support.owner.relation ++
      " -> EVIDENCE " ++ displayKey support.owner.outcome ++
      "\\n  [Surrounding evidence reached through the saved graph, not a completion judgment.]")
    support.provenance original).map fun data =>
      {original with keys := data.keys, text := data.text, context := data.context}

theorem prepareContextualSupportPlan_exact (delivered : List String) (windows : List Nat)
    (support : SourceSupport roots all unions) :
    (prepareContextualSupportPlan delivered windows support).eval =
      prepareContextualSupportSlice delivered windows support := by
  funext budget
  unfold prepareContextualSupportPlan prepareContextualSupportSlice prepareContextualOwnerSlice
  rw [BudgetPlan.eval_map, prepareContextualOwnerPlan_exact]

'''


def handoff(source):
    source = once(source, 'public import Eggshell.PluginModel\n',
        'public import Eggshell.PluginModel\npublic import tools.BudgetPlan\n')
    source = once(source, 'theorem coherent_context_ranges_keep_cues', '''/-- Name source scans before the partially applied function. Its default
argument otherwise puts those scans inside every range's map iteration. -/
def coherentContextRangesFast (source : String) (ranges : List (EvidenceRange source)) :
    List (EvidenceRange source) :=
  let layout := (decodedToolText? source).map DecodedLayout.make
  let records := contextRecordSpans source layout
  let heads := contextStructureHeads source layout
  ranges.map (coherentRecordContext records heads)

@[csimp] theorem coherentContextRanges_compiled : @coherentContextRanges = @coherentContextRangesFast := by
  rfl

theorem coherent_context_ranges_keep_cues''')
    lo = source.index('def prepareContextualOwnerPart (')
    hi = source.index('def prepareContextualOwnerData (', lo)
    body = source[lo:hi].rstrip()
    body = once(body, 'def prepareContextualOwnerPart (', '@[noinline] def prepareContextualOwnerPlan (')
    body = once(body, '(slice : TransportSlice) : Nat → Option DeliveryPart :=',
        '(slice : TransportSlice) : BudgetPlan DeliveryPart :=')
    if body.count('fun _ => some {keys := slice.keys, text := slice.text}') != 2 or body.count('fun _ => none') != 2:
        raise ValueError('Audit the complete constant/contextual branch boundary')
    body = body.replace('fun _ => some {keys := slice.keys, text := slice.text}',
        '.constant (some {keys := slice.keys, text := slice.text})').replace('fun _ => none', '.constant none')
    body = once(body, '          fun contextBudget => do', '          .sized fun contextBudget => do')
    boundary = source.index('theorem contextual_support_has_no_control')
    source = source[:boundary] + body + '\n\n' + PROOFS + source[boundary:]
    source = once(source, 'let render := prepareContextualSlice planningReceipts windows slice',
        'let render := (prepareContextualSlicePlan planningReceipts windows slice).eval')
    return once(source, 'let render := prepareContextualSupportSlice planningReceipts windows source',
        'let render := (prepareContextualSupportPlan planningReceipts windows source).eval')


def audit(source):
    source = once(source, '  for theoremName in #[``Eggshell.Extract.solve_demand_exact,',
        '''  for theoremName in #[``Eggshell.Plugin.prepareContextualOwnerPlan_exact,
      ``Eggshell.Plugin.prepareContextualSlicePlan_exact,
      ``Eggshell.Plugin.prepareContextualSupportPlan_exact,
      ``Eggshell.Plugin.coherentContextRanges_compiled,
      ``Eggshell.Extract.solve_demand_exact,''')
    source = once(source,
        '``Eggshell.Plugin.prepareContextualOwnerPart, ``Eggshell.Plugin.coalesceRankedContexts,',
        '''``Eggshell.Plugin.prepareContextualOwnerPlan,
          ``Eggshell.Plugin.prepareContextualSlicePlan,
          ``Eggshell.Plugin.prepareContextualSupportPlan, ``Eggshell.BudgetPlan.eval,
          ``Eggshell.Plugin.coalesceRankedContexts,''')
    # Actual runtime reachability above must target the new producer. These
    # typed checks additionally bind all three universal equalities to their
    # exact original specifications; changing a theorem's scope cannot pass.
    return source + '''
example (delivered : List String) (windows : List Nat)
    (owner : Eggshell.OutcomeEdge) (connections : String)
    (records : List Eggshell.SourceEvidence.Record) (slice : Eggshell.Plugin.TransportSlice) :
    (Eggshell.Plugin.prepareContextualOwnerPlan delivered windows owner connections records slice).eval =
      Eggshell.Plugin.prepareContextualOwnerPart delivered windows owner connections records slice :=
  Eggshell.Plugin.prepareContextualOwnerPlan_exact delivered windows owner connections records slice

example (delivered : List String) (windows : List Nat) (slice : Eggshell.Plugin.TransportSlice) :
    (Eggshell.Plugin.prepareContextualSlicePlan delivered windows slice).eval =
      Eggshell.Plugin.prepareContextualSlice delivered windows slice :=
  Eggshell.Plugin.prepareContextualSlicePlan_exact delivered windows slice

example (roots : List Eggshell.Value) (all : List Eggshell.AllEdge) (unions : List Eggshell.UnionEdge)
    (delivered : List String) (windows : List Nat)
    (support : Eggshell.Plugin.SourceSupport roots all unions) :
    (Eggshell.Plugin.prepareContextualSupportPlan delivered windows support).eval =
      Eggshell.Plugin.prepareContextualSupportSlice delivered windows support :=
  Eggshell.Plugin.prepareContextualSupportPlan_exact delivered windows support
'''
