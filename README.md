# Nimna

A private line between two people. Paid, account-less, synchronous-only,
end-to-end-encrypted 1:1 messaging: a stateless relay routes ciphertext
between two live devices and never stores anything — no accounts, no
history sync, no server-side anything.

**Protocol:** [`docs/nimna-protocol-spec-v0.2.1.md`](docs/nimna-protocol-spec-v0.2.1.md)
(single source of truth; v0.2 and v0.1.1 remain as history). **Build plan:**
[`nimna-build-plan-v2-sessions.md`](nimna-build-plan-v2-sessions.md).

## Layout

| Path | Contents |
|---|---|
| [`application/`](application/) | Product code: [`relay/`](application/relay/) (Go, AGPL-3.0, opens at Session 6) · [`mobile/`](application/mobile/) (Flutter, closed) |
| [`designs/`](designs/) | Brand, design system, wireframes, hi-fi screens, handoff — binding for UI |
| [`website/`](website/) | nimna.app static site |
| [`docs/`](docs/) | Spec copy, test vectors (S2+), architecture notes, archive |
| `TASKS.md` / `PROGRESS.md` / `DECISIONS.md` | Work-loop tracking: status board, append-only log, decision record |

Working conventions for build sessions live in [`CLAUDE.md`](CLAUDE.md).
CI (relay + mobile lint/test) lives in `.github/workflows/`.
