module

import Eggshell
public meta import Lean

open Lean

/- Former computed fixtures must not leak back through public imports. -/
run_meta do
  let environment ← getEnv
  for name in #[
      `Eggshell.Laws.direct_outcome_is_context_not_completion,
      `Eggshell.Laws.all_erases_only_covered_work,
      `Eggshell.Laws.local_union_resaturates_into_prior_work,
      `Eggshell.Laws.advisory_is_visible_without_erasure,
      `Eggshell.Laws.semantic_congruence_closes_after_union,
      `Eggshell.Laws.exact_arguments_never_follow_semantic_union,
      `Eggshell.Laws.union_collapses_duplicate_subwork_in_extracted_dag,
      `Eggshell.Laws.extraction_chooses_smallest_saturated_graph,
      `Eggshell.MatcherLaws.top_level_shell_clauses_are_independent,
      `Eggshell.MatcherLaws.quoted_substitution_stays_atomic,
      `Eggshell.MatcherLaws.shell_control_program_stays_atomic,
      `Eggshell.MatcherLaws.canonical_native_work_has_a_match_view,
      `Eggshell.MatcherLaws.regex_dot_preserves_work_units,
      `Eggshell.MatcherLaws.prose_dot_preserves_one_work_value,
      `Eggshell.MatcherLaws.quoted_regex_does_not_invent_subwork,
      `Eggshell.MatcherLaws.unquoted_pipe_stays_inside_native_work,
      `Eggshell.MatcherLaws.quoted_regex_alternative_stays_advisory,
      `Eggshell.MatcherLaws.local_union_changes_the_selected_work_graph,
      `Eggshell.MatcherLaws.semantic_retrieval_does_not_union_or_complete,
      `Eggshell.MatcherLaws.local_union_preserves_outcome_ownership,
      `Eggshell.MatcherLaws.native_result_is_advisory_not_a_local_union,
      `Eggshell.MatcherLaws.one_local_union_per_value_pair,
      `Eggshell.MatcherLaws.contained_work_is_reusable_but_the_inquiry_stays_open,
      `Eggshell.MatcherLaws.forward_containment_erases_only_the_historical_work,
      `Eggshell.MatcherLaws.forward_containment_uses_structural_outcome_ownership,
      `Eggshell.MatcherLaws.reverse_containment_stays_advisory_even_when_result_text_is_grounded,
      `Eggshell.MatcherLaws.nestedWork,
      `Eggshell.MatcherLaws.local_union_resaturates_newly_demanded_subwork,
      `Eggshell.MatcherLaws.historicalTurnFrame,
      `Eggshell.MatcherLaws.parent_turn_outcome_cannot_erase_a_native_operation,
      `Eggshell.MatcherLaws.projection_preserves_the_whole_outcome,
      `Eggshell.MatcherLaws.parent_turn_fragment_is_not_automatic,
      `Eggshell.MatcherLaws.advisoryParentFrame,
      `Eggshell.MatcherLaws.parent_turn_projects_grounded_advice_without_erasing_work,
      `Eggshell.MatcherLaws.parent_advice_does_not_demand_unmatched_historical_children,
      `Eggshell.MatcherLaws.enclosing_past_work_is_advisory_not_completed,
      `Eggshell.MatcherLaws.projected_fragment_is_an_ordinary_outcome,
      `Eggshell.MatcherLaws.outcome_text_cannot_enter_demand_without_work_identity,
      `Eggshell.MatcherLaws.echoed_command_in_outcome_never_completes_work,
      `Eggshell.MatcherLaws.transport_scaffolding_is_advisory,
      `Eggshell.MatcherLaws.oriented_native_occurrence_is_native,
      `Eggshell.MatcherLaws.oriented_turn_occurrence_is_not_native,
      `Eggshell.MatcherLaws.native_option_scaffolding_never_completes_work,
      `Eggshell.MatcherLaws.completed_native_clause_reuses_grounded_outcome_and_keeps_remainder,
      `Eggshell.MatcherLaws.different_native_clause_range_stays_advisory,
      `Eggshell.MatcherLaws.distinctive_fragment_is_reusable_without_closing_the_inquiry,
      `Eggshell.MatcherLaws.one_distinctive_anchor_keeps_partial_work_advisory,
      `Eggshell.MatcherLaws.shell_scaffolding_does_not_complete_an_atomic_native_work,
      `Eggshell.MatcherLaws.fragment_union_does_not_invent_completed_work,
      `Eggshell.MatcherLaws.pipeline_overlap_stays_advisory,
      `Eggshell.MatcherLaws.grounded_prose_reverse_containment_stays_advisory,
      `Eggshell.MatcherLaws.grounded_half_overlap_is_advisory_delivery,
      `Eggshell.MatcherLaws.dominant_partial_fragment_stays_advisory,
      `Eggshell.MatcherLaws.transport_flag_variation_keeps_current_clause_open,
      `Eggshell.MatcherLaws.shared_target_reuses_observation_without_closing_demand,
      `Eggshell.MatcherLaws.different_native_targets_are_advisory_only,
      `Eggshell.MatcherLaws.equivalent_native_target_is_locally_unioned_and_completed,
      `Eggshell.MatcherLaws.path_suffix_overlap_never_completes_another_file,
      `Eggshell.MatcherLaws.relative_path_spelling_preserves_operation_identity,
      `Eggshell.Blake3.empty_vector,
      `Eggshell.Blake3.abc_vector] do
    if (environment.find? name).isSome then
      throwError "Computed fixture leaked into production: {name}"
  for theoremName in #[``Eggshell.Matcher.extraction_sound,
      ``Eggshell.Matcher.extraction_completed_has_match,
      ``Eggshell.QuotientBuilder.CongruenceSound.build_sound] do
    let axioms ← Lean.collectAxioms theoremName
    for axiomName in axioms do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains axiomName do
        throwError "Production completion theorem uses an unapproved axiom: {theoremName}: {axiomName}"
  logInfo "Audited production fixture exclusion and completion theorem axioms"
