# Splash depth ladder — Qwen3.8-27B-Splash (4-bit + DFlash2), 2026-09-27

LM Studio 0.4.25, Splash runtime 0.0.5, M5 Pro / 64 GB, ctx 262144. Same method as
`vacation-run/STRESS-GGUF.md` Phase B: one real Claude Code session; turn N reads
`stress-corpus/fileN.md` (~120 KB) and must recall its planted designation.
Driver: `run-ladder.sh`. Raw per-turn output and LM Studio request logs in `turns/`.

| turn | depth (tokens) | wall | recall | wired | free RAM |
|---|---|---|---|---|---|
| B1 | 62,418 | 192 s | yes | 21.8 GB | 61% |
| B2 | 107,484 | 450 s | yes | 27.6 GB | 53% |
| B3 | 154,057 | 526 s | yes | 32.4 GB | 44% |
| B4 | 198,609 | 824 s | yes | 37.8 GB | 31% |
| B5 | 227,078 | 1347 s | yes | 44.8 GB | 13% |

Stopped manually before B6: wired was 44.8 GB against the 50 GB iogpu limit (the panic
zone in earlier campaigns), and B6 would have exceeded the 262k window. Zero panics.

Compared with gguf5 (llama.cpp, STRESS-GGUF.md): gguf5's deepest correct turn was
158,766 tokens, with B1–B3 at 462 / 874 / 1533 s against Splash's 192 / 450 / 526 s.

Cache: after each turn's first request, 93–100% of the prompt was cached. Cold misses
happened when a request's prompt diverged from the single stored prefix, e.g. B2's
first request after `--resume` carried a different tool list. Decode ran 26–50 t/s at
depth. Warm prefill ran ~250–480 tok/s.

Note: the question template names a "sealed reference core". That only matches file1,
so on B2–B5 the model found the right designation and correctly pointed out the
premise mismatch. Recall is still valid.
