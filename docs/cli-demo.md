# Two chats. Less repeated work.

[Project home](../README.md) · [Try it yourself](try-it.md) · [Measurement record](benchmarks/cli-demo.json)

https://github.com/user-attachments/assets/939eca34-4897-4bcf-9dbc-a6326bc9ba3a

This 29-second demo uses actual Codex CLI recordings with **Luna xhigh** and
**independent ephemeral chats**. One chat investigates Clang’s toolchain selection.
Two new chats receive the same related question: one starts fresh with Eggshell
hooks disabled; the other receives relevant findings from the saved `.egg`.

The recording highlights the handoff delivery and the agent’s explicit reuse
statement. Elapsed time is compressed, with pauses for those annotations. The
terminal output and measured token totals are unchanged.

## The recorded comparison

| Work | Fresh + fresh | Fresh + Eggshell |
| --- | ---: | ---: |
| Shared first investigation | 835,305 | 835,305 |
| Second-chat follow-up | 1,074,497 | 195,368 |
| Both chats | 1,909,802 | 1,030,673 |

**81.8% fewer tokens in the second chat; 46.0% fewer across both chats.**
The same first investigation is charged to both routes. Tokens mean input plus
output, including cached input; reasoning is already included in output. These
are token counts, not dollar-cost estimates. Memory organization makes no extra
LLM calls; the selected handoff still consumes normal model input tokens.

Both final answers passed five static-source review criteria covering selection
order, wrapper restrictions, relevant source/tests, and accurate reporting of
what was not run. This was one recorded pair and a single non-blinded reviewer,
without Clang runtime tests. It does not establish general savings or equivalent
answer quality across tasks. The README’s [ten-trial study](../README.md#evidence)
and its [earlier walkthrough](demo.md) are a separate experiment.

## The follow-up question

```text
In this Clang source snapshot, can an architecture-scoped -Xarch_* argument
change the already selected host toolchain in the same way that a direct
-target, -m32, or -m64 option can? Explain the relevant ordering and constraints,
with function names and source-line citations, and identify a relevant existing
driver test. Keep the final answer within 250 words. Do not modify files or
build LLVM. Distinguish static source findings from untested runtime behavior.
```

Both follow-ups used the same prompt, model, effort, and fixed
[LLVM source commit](https://github.com/llvm/llvm-project/tree/6dfe1677ab8dffbc6ec13d53a1e0215d75147689).
Source, prompt, prior-work, runtime, answer and video hashes are included in the
[measurement record](benchmarks/cli-demo.json). Raw private execution logs remain
local; hashes identify those records but are not a substitute for access to them.

The key ordering is visible in [host toolchain selection](https://github.com/llvm/llvm-project/blob/6dfe1677ab8dffbc6ec13d53a1e0215d75147689/clang/lib/Driver/Driver.cpp#L1695-L1722)
and [per-toolchain argument translation](https://github.com/llvm/llvm-project/blob/6dfe1677ab8dffbc6ec13d53a1e0215d75147689/clang/lib/Driver/Compilation.cpp#L63-L111).
