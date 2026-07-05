# /designs/screens — Hi-Fi Screens (Task 2, §5)

HTML/CSS mockups, one file per screen, mobile viewport **390×844**, pixel values from [`../system/tokens.json`](../system/tokens.json) exactly via [`screens.css`](screens.css). Open any file in a browser; screenshot with headless Chrome at window 438×900. Dark is the hero mode; light variants share identical markup with the `light` token class.

| # | Screen | Flow | Dark | Light |
|---|---|---|---|---|
| 01 | Onboarding 1 — what it is | F1 | [01-onboarding-1.html](01-onboarding-1.html) | — |
| 02 | Create a code (QR + copy/share + waiting line) | F2 | [02-create-code.html](02-create-code.html) | [✓](02-create-code.light.html) |
| 03 | Safety phrase comparison | F2/F3 | [03-safety-phrase.html](03-safety-phrase.html) | — |
| 04 | Channel list (unlocked) | F4 | [04-channel-list.html](04-channel-list.html) | [✓](04-channel-list.light.html) |
| 05 | Live chat (on the line) — v0.2.1: reaction chip + quoted reply in-thread | F5 | [05-live-chat.html](05-live-chat.html) | [✓](05-live-chat.light.html) |
| 06 | Knock received (in-app banner) | F6 | [06-knock-received.html](06-knock-received.html) | — |
| 07 | Disappearing composer (timer sheet + honor-system copy) | F5 | [07-disappearing-composer.html](07-disappearing-composer.html) | — |
| 08 | Panic wipe confirm (hold-to-wipe) | F8 | [08-panic-wipe-confirm.html](08-panic-wipe-confirm.html) | — |
| 09 | Paywall | F9 | [09-paywall.html](09-paywall.html) | [✓](09-paywall.light.html) |
| 10 | Enter their code (9-seg XXX-XXX-XXX + paste/scan/upload) | F3 | [10-enter-code.html](10-enter-code.html) | — |
| 11 | Chat waiting (offline outbox + knocked-waiting patience state) | F5 | [11-chat-waiting.html](11-chat-waiting.html) | — |
| 12 | App lock (zero-leak) | F12/F8 | [12-app-lock.html](12-app-lock.html) | — |
| 13 | Media viewer (export as the deliberate act) — v0.1.1 | F5 | [13-media-viewer.html](13-media-viewer.html) | — |
| 14 | Sensitive media, blurred (on-device check) — v0.1.1 | F5 | [14-sensitive-blur.html](14-sensitive-blur.html) | — |
| 15 | Attach whisper (sensitive-content check at attach) — v0.1.1 | F5 | [15-whisper-attach.html](15-whisper-attach.html) | — |
| 16 | Message actions — react/reply entry (long-press card, emoji quick row) — v0.2.1 | F5 | [16-message-actions.html](16-message-actions.html) | — |

Notes
- Synced to protocol spec v0.1.1 (2026-07-04): media in chat + system screenshot line (05), subscription paywall with permanence guarantee (09), 9-char hyphenated Nimna code (02, 10), four join methods (10), "call them and compare" framing (03), knock patience caption (11), onboarding grows to 4 panes (01 dots), net-new 13–15.
- The 9 spec-mandated screens are 01–09; 10–15 are free-choice + v0.1.1 additions. Light variants: 02, 04, 05, 09 (sed-regenerated from dark; see git history).
- **No price appears anywhere by doctrine (spec §10):** the paywall CTA renders the literal `{STORE_PRICE}` placeholder — at build it becomes the store's localized price string (StoreKit / Play Billing). Never hardcode a number.
- The knock/reconnect line animations run live in-browser (`@keyframes breathe`); `prefers-reduced-motion` freezes them solid.
- QR in 02 is a deterministic mock pattern, not a scannable code. Media "photos" in 05/13/14/15 are CSS-gradient mocks — no image assets.
- Design-sync 2026-07-05 to spec v0.2.1: 05 gains their ❤️ chip on the media bubble and a quoted reply composing with the disappearing timer (`reply_to` + `expiry_s` compose freely — spec §5.8); net-new 16 shows the long-press react/reply card (preset emoji row is a proposed default, pending USER confirm). Chips carry no delivery chrome — REACTION is never ACKed (spec §5.8) — and never amber. Both 05 variants and 16 Chrome-render-verified at 438×900.
