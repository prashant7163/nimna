# /designs/screens — Hi-Fi Screens (Task 2, §5)

HTML/CSS mockups, one file per screen, mobile viewport **390×844**, pixel values from [`../system/tokens.json`](../system/tokens.json) exactly via [`screens.css`](screens.css). Open any file in a browser; screenshot with headless Chrome at window 438×900. Dark is the hero mode; light variants share identical markup with the `light` token class.

| # | Screen | Flow | Dark | Light |
|---|---|---|---|---|
| 01 | Onboarding 1 — what it is | F1 | [01-onboarding-1.html](01-onboarding-1.html) | — |
| 02 | Create a code (QR + copy/share + waiting line) | F2 | [02-create-code.html](02-create-code.html) | [✓](02-create-code.light.html) |
| 03 | Safety phrase comparison | F2/F3 | [03-safety-phrase.html](03-safety-phrase.html) | — |
| 04 | Channel list (unlocked) | F4 | [04-channel-list.html](04-channel-list.html) | [✓](04-channel-list.light.html) |
| 05 | Live chat (on the line) | F5 | [05-live-chat.html](05-live-chat.html) | [✓](05-live-chat.light.html) |
| 06 | Knock received (in-app banner) | F6 | [06-knock-received.html](06-knock-received.html) | — |
| 07 | Disappearing composer (timer sheet + honor-system copy) | F5 | [07-disappearing-composer.html](07-disappearing-composer.html) | — |
| 08 | Panic wipe confirm (hold-to-wipe) | F8 | [08-panic-wipe-confirm.html](08-panic-wipe-confirm.html) | — |
| 09 | Paywall | F9 | [09-paywall.html](09-paywall.html) | [✓](09-paywall.light.html) |
| 10 | Enter their code (segmented entry) | F3 | [10-enter-code.html](10-enter-code.html) | — |
| 11 | Chat waiting (offline outbox + knock countdown) | F5 | [11-chat-waiting.html](11-chat-waiting.html) | — |
| 12 | App lock (zero-leak) | F12/F8 | [12-app-lock.html](12-app-lock.html) | — |

Notes
- The 9 spec-mandated screens are 01–09; 10–12 are the free-choice picks (decision record). Light variants: 02, 04, 05, 09.
- **Open item:** paywall price is deliberately unspecified ("Unlock — one payment") — pricing is a USER decision, pending.
- The knock/reconnect line animations run live in-browser (`@keyframes breathe`); `prefers-reduced-motion` freezes them solid.
- QR in 02 is a deterministic mock pattern, not a scannable code.
