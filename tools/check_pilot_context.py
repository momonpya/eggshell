#!/usr/bin/env python3
"""Counterfactual checks for native, pasted and fresh pilot context evidence."""
from __future__ import annotations

from copy import deepcopy
import json
import unittest

from pilot_context import audit_context, observed_output, previous_answer_prompt, recorded_answer


def message(role, text, **extra):
    return dict(type="message", role=role, content=[dict(type="input_text", text=text)], **extra)


class ContextEvidenceControls(unittest.TestCase):
    def setUp(self):
        self.answer = "Recorded answer: preserve failure handling."
        self.question = "Add a byte budget."
        self.prior = dict(input=[message("developer", "platform instructions"),
            message("user", "<environment_context>\nfixed workspace"), message("user", "Inspect the loader."),
            dict(type="custom_tool_call", name="exec", call_id="read", input="source-read-command"),
            dict(type="custom_tool_call_output", call_id="read", output=[dict(type="input_text", text=json.dumps(
                dict(exit_code=0, output="original source bytes\n")))])])
        self.continued = dict(input=self.prior["input"] + [
            message("assistant", self.answer, phase="final_answer"), message("user", self.question)])

    def audit(self, body, condition):
        return audit_context(body, condition, self.question, self.answer, self.prior)

    def test_three_intended_contexts_are_distinct(self):
        fresh = dict(input=[message("user", self.question)])
        pasted = dict(input=[message("user", previous_answer_prompt(self.question, self.answer))])
        self.assertTrue(self.audit(self.continued, "same-chat")["native_history"])
        self.assertTrue(self.audit(pasted, "previous-answer")["pasted_answer"])
        self.assertFalse(self.audit(fresh, "fresh")["native_history"])

    def test_dropped_native_observation_is_rejected(self):
        body = deepcopy(self.continued)
        del body["input"][4]
        with self.assertRaisesRegex(ValueError, "history"):
            self.audit(body, "same-chat")

    def test_modified_native_observation_is_rejected(self):
        body = deepcopy(self.continued)
        body["input"][4]["output"][0]["text"] = "invented bytes"
        with self.assertRaisesRegex(ValueError, "history"):
            self.audit(body, "same-chat")

    def test_pasted_history_does_not_qualify_as_native_continuation(self):
        body = dict(input=[message("user", json.dumps(self.continued) + self.question)])
        with self.assertRaises(ValueError):
            self.audit(body, "same-chat")

    def test_assistant_role_cannot_be_spoofed_by_a_developer_message(self):
        body = deepcopy(self.continued)
        body["input"][-2]["role"] = "developer"
        with self.assertRaises(ValueError):
            self.audit(body, "same-chat")

    def test_pasted_condition_rejects_native_tool_history(self):
        body = dict(input=[self.prior["input"][-1],
                          message("user", previous_answer_prompt(self.question, self.answer))])
        with self.assertRaises(ValueError):
            self.audit(body, "previous-answer")

    def test_fresh_rejects_prior_answer_in_hidden_context(self):
        body = dict(input=[message("developer", self.answer), message("user", self.question)])
        with self.assertRaises(ValueError):
            self.audit(body, "fresh")

    def test_new_thread_rejects_an_extra_prior_user_message(self):
        body = dict(input=[message("user", "Inspect the loader."), message("user", self.question)])
        with self.assertRaises(ValueError):
            self.audit(body, "fresh")

    def test_previous_answer_is_preserved_with_quotes_unicode_and_newlines(self):
        self.answer = '前の回答 "quoted"\nsecond line'
        prompt = previous_answer_prompt(self.question, self.answer)
        self.assertEqual(json.loads(prompt)["previous_answer"], self.answer)
        self.audit(dict(input=[message("user", prompt)]), "previous-answer")
        with self.assertRaises(ValueError):
            self.audit(dict(input=[message("user", self.question)]), "previous-answer")

    def test_unloaded_or_ambiguous_final_answer_is_rejected(self):
        turn = dict(id="prior", status="completed", itemsView="full", items=[
            dict(type="agentMessage", phase="final_answer", text=self.answer)])
        self.assertEqual(recorded_answer(dict(turns=[turn]), "prior"), self.answer)
        for changes in [dict(status="failed"), dict(itemsView="notLoaded"), dict(items=turn["items"] * 2),
                        dict(items=[dict(type="agentMessage", phase="commentary", text=self.answer)])]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                recorded_answer(dict(turns=[dict(turn, **changes)]), "prior")

    def test_source_in_program_text_is_not_observed_output(self):
        body = deepcopy(self.prior)
        body["input"][-2]["input"] = "original source bytes\n"
        body["input"][-1]["output"][0]["text"] = json.dumps(dict(exit_code=1, output="original source bytes\n"))
        with self.assertRaises(ValueError):
            observed_output(body, "original source bytes\n")
        self.assertEqual(observed_output(self.prior, "original source bytes\n"), "original source bytes\n")

    def test_unlinked_or_truncated_tool_result_is_rejected(self):
        for modification in ["call", "body"]:
            body = deepcopy(self.prior)
            if modification == "call":
                body["input"][-1]["call_id"] = "wrong"
            else:
                body["input"][-1]["output"][0]["text"] = json.dumps(dict(exit_code=0, output="original"))
            with self.subTest(modification=modification), self.assertRaises(ValueError):
                observed_output(body, "original source bytes\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
