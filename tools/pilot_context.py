"""Explicit context boundaries for the three non-Eggshell pilot conditions."""
from __future__ import annotations

import hashlib
import json


CONDITIONS = {"fresh", "previous-answer", "same-chat"}


def text_parts(item):
    return [part["text"] for part in item.get("content", [])
            if part.get("type") in {"input_text", "output_text"}]


def previous_answer_prompt(question, answer):
    if not question or not answer:
        raise ValueError("Both the current question and recorded prior answer are required")
    return json.dumps(dict(previous_answer=answer, current_task=question), ensure_ascii=False, indent=2)


def recorded_answer(thread, turn_id):
    turns = [turn for turn in thread["turns"] if turn["id"] == turn_id]
    if len(turns) != 1 or turns[0]["status"] != "completed" or turns[0].get("itemsView", "full") != "full":
        raise ValueError("Prior turn is absent, incomplete or not fully loaded")
    answers = [item["text"] for item in turns[0]["items"]
               if item["type"] == "agentMessage" and item.get("phase") == "final_answer"]
    if len(answers) != 1 or not answers[0]:
        raise ValueError("A unique recorded final answer is required")
    return answers[0]


def observed_output(body, expected):
    calls = [item for item in body["input"] if item.get("type") == "custom_tool_call"]
    outputs = [item for item in body["input"] if item.get("type") == "custom_tool_call_output"]
    if (len(calls) != 1 or len(outputs) != 1 or calls[0].get("name") != "exec"
            or not calls[0].get("call_id") or outputs[0].get("call_id") != calls[0]["call_id"]):
        raise ValueError("A single linked native command result is required")
    results = []
    for part in outputs[0]["output"]:
        if part.get("type") != "input_text":
            continue
        try:
            row = json.loads(part["text"])
        except (ValueError, TypeError):
            continue
        if isinstance(row, dict) and "exit_code" in row and "output" in row:
            results.append(row)
    if len(results) != 1 or results[0]["exit_code"] != 0 or results[0]["output"] != expected:
        raise ValueError("Exact successful native command output was not observed")
    return results[0]["output"]


def audit_context(body, condition, question, answer, prior_request):
    if condition not in CONDITIONS:
        raise ValueError("Unknown context condition")
    inputs = body["input"]
    current = previous_answer_prompt(question, answer) if condition == "previous-answer" else question
    messages = [item for item in inputs if item.get("type") == "message"]
    if sum(item.get("role") == "user" and text_parts(item) == [current] for item in messages) != 1:
        raise ValueError("The exact current input must occur once in a user message")
    if condition == "same-chat":
        prior = prior_request["input"]
        if inputs[:len(prior)] != prior:
            raise ValueError("Native prior history was changed or omitted")
        tail = inputs[len(prior):]
        if (len(tail) != 2 or tail[0].get("type") != "message" or tail[0].get("role") != "assistant"
                or text_parts(tail[0]) != [answer] or tail[0].get("phase") != "final_answer"
                or tail[1].get("type") != "message" or tail[1].get("role") != "user"
                or text_parts(tail[1]) != [question]):
            raise ValueError("Native continuation must append the recorded answer and current question")
    else:
        if any(item.get("type") not in {"message", "additional_tools"} or item.get("role") == "assistant"
               for item in inputs):
            raise ValueError("A new-thread condition inherited native tool or assistant history")
        # The only additional user message allowed is the CLI's environment context.
        if any(text_parts(item) != [current] and not (
                len(text_parts(item)) == 1 and text_parts(item)[0].startswith("<environment_context>\n"))
                for item in messages if item.get("role") == "user"):
            raise ValueError("Unexpected prior user context in a new thread")
        prior_user = [text for item in prior_request["input"]
                      if item.get("type") == "message" and item.get("role") == "user"
                      for text in text_parts(item) if not text.startswith("<environment_context>\n")]
        other_text = "\n".join(text for item in messages if text_parts(item) != [current]
                               for text in text_parts(item))
        if any(text in other_text for text in [answer, *prior_user]):
            raise ValueError("Prior answer or question leaked outside the declared context")
        if condition == "fresh" and any(answer in text for item in messages for text in text_parts(item)):
            raise ValueError("Fresh condition contains the prior answer")
    raw = json.dumps(inputs, sort_keys=True).encode()
    return dict(condition=condition, input_sha256=hashlib.sha256(raw).hexdigest(),
                prior_answer_sha256=hashlib.sha256(answer.encode()).hexdigest(),
                native_history=condition == "same-chat", pasted_answer=condition == "previous-answer")
