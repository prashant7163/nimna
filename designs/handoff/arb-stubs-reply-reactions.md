# ARB stubs — reply / reactions / self-join guard (design-sync DS, spec v0.2.1)

**Handoff artifact, not a live l10n file.** The live `application/mobile/lib/l10n/*.arb`
files belong to in-flight Session 7; per the parallel-session hotspot rule
(DECISIONS 2026-07-05 02:58), DS ships these keys here and the **orchestrator folds
them into `lib/l10n` at DS's merge**. Keys are namespaced per that rule: `chat_…`
for the reply/reaction surfaces, `pairing_…` for the self-join guard.

Every value is voice-guide canonical (strings 19–21, `designs/brand/voice-and-microcopy.md`);
the two spec-canonical strings are verbatim from spec v0.2.1 (§3.1, §5.8) and must never
be edited outside a spec change. **DE/FR/ES/IT renderings ride the S16 crafted
translation pass** (claim-accuracy exact, PM-reviewed, disputes → USER) **and the
project's untranslated-key tracker until then** — do not machine-fill.

## EN key/value JSON (fold verbatim into the EN ARB)

```json
{
  "chat_messageActionReply": "Reply",
  "@chat_messageActionReply": {
    "description": "Message-actions card: starts a reply to the long-pressed message (voice string 21 family; components.md message actions)."
  },
  "chat_messageActionReact": "React",
  "@chat_messageActionReact": {
    "description": "Message-actions card: a11y/name for the emoji quick row (voice string 21). The visible affordance is the emoji row itself."
  },
  "chat_messageActionDelete": "Delete",
  "@chat_messageActionDelete": {
    "description": "Message-actions card: the local per-message delete (spec section 6). Rides the same card as react/reply; previously long-press to delete on waiting bubbles."
  },
  "chat_replyingToLabel": "Replying to",
  "@chat_replyingToLabel": {
    "description": "Reply compose strip overline (voice string 20). Rendered as the micro uppercase style; casing is a text-style concern, not a copy concern."
  },
  "chat_replyCancelA11y": "Cancel reply",
  "@chat_replyCancelA11y": {
    "description": "A11y label for the X that abandons the reply compose strip (voice string 20). Composer text survives cancellation."
  },
  "chat_replyTombstone": "Message no longer available.",
  "@chat_replyTombstone": {
    "description": "CANONICAL, spec v0.2.1 section 5.8 verbatim. Quote-block tombstone when the referenced message is unknown, deleted, or expired - one identical string for all three causes; it never says why. Never edit outside a spec change."
  },
  "chat_replyPreviewPhoto": "Photo",
  "@chat_replyPreviewPhoto": {
    "description": "Quoted-media preview label beside the 32 px thumbnail when the referenced message is an image (voice string 20)."
  },
  "chat_replyPreviewDocument": "Document",
  "@chat_replyPreviewDocument": {
    "description": "Quoted-media preview label beside the thumbnail when the referenced message is a document (voice string 20)."
  },
  "chat_reactionOwnA11y": "You reacted {emoji}. Tap to remove.",
  "@chat_reactionOwnA11y": {
    "description": "A11y label for your own reaction chip (voice string 21). Tap removes unconditionally (spec section 5.8).",
    "placeholders": {
      "emoji": {
        "type": "String",
        "example": "👍"
      }
    }
  },
  "chat_reactionPeerA11y": "They reacted {emoji}.",
  "@chat_reactionPeerA11y": {
    "description": "A11y label for the peer's reaction chip (voice string 21). 'They' is deliberate - the peer has no name; the channel label is local-only.",
    "placeholders": {
      "emoji": {
        "type": "String",
        "example": "❤️"
      }
    }
  },
  "chat_reactionPickMoreA11y": "Choose another emoji",
  "@chat_reactionPickMoreA11y": {
    "description": "A11y label for the plus disc at the end of the emoji quick row - opens the system emoji keyboard; first emoji grapheme is taken (compose rule, spec section 5.5)."
  },
  "pairing_selfJoinOwnCode": "This is your own Nimna code — share it with the other person.",
  "@pairing_selfJoinOwnCode": {
    "description": "CANONICAL, spec v0.2.1 section 3.1 verbatim (voice string 19). Self-join guard on the code-entry surface: detected locally, nothing is sent, warning-toned, no shake. Never edit outside a spec change."
  }
}
```

## Notes for the fold

- **Placeholders:** only the two chip-a11y keys carry one (`{emoji}`, `String`). The
  substituted value is the raw wire emoji field — already clamped by the chip render
  rule (components.md); no formatting, no plural, no gender anywhere in this set.
- **Plurals:** none needed. Reactions are at most one per sender per message (spec §5.8),
  and a 1:1 line means at most two chips.
- **Key casing/shape** may be normalized to S7's established ARB conventions at fold
  time; the **namespaces (`chat_`, `pairing_`) and the values are binding** — values
  for the two canonical strings byte-for-byte (em dash in `pairing_selfJoinOwnCode`
  included).
- **German-length check (standing i18n rule):** the layouts these keys land in were
  specced for it — tombstone and self-join message each tolerate two caption lines;
  quoted excerpts ellipsize; chip a11y strings are non-visual.
- Voice-guide mapping: string 19 → `pairing_selfJoinOwnCode` · string 20 →
  `chat_replyingToLabel`, `chat_replyCancelA11y`, `chat_replyTombstone`,
  `chat_replyPreviewPhoto`, `chat_replyPreviewDocument` · string 21 →
  `chat_messageActionReact`, `chat_reactionOwnA11y`, `chat_reactionPeerA11y`,
  `chat_reactionPickMoreA11y` (+ card labels `chat_messageActionReply`,
  `chat_messageActionDelete`).
