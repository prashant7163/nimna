# Nimna — Voice & Microcopy Guide (1.4)

*Synced to protocol spec v0.1.1 (2026-07-04): pricing model, screenshot policy, sensitive-content handling, media, pairing enrichments, push, device-loss doctrine.*

## The voice

Nimna speaks like someone who has nothing to prove and nothing to hide. Plain words, short sentences, present tense. It states what the architecture does instead of promising what the company will do. It admits limits without flinching — honesty about the threat model is a brand asset, not a disclaimer to bury.

**Principles**

1. **Facts, not vows.** "Nothing is stored anywhere" — verifiable architecture. Never "we would never read your messages" — that's a promise about intent.
2. **Say the limit out loud.** Disappearing messages can't stop a screenshot. Say so, plainly, where the feature lives.
3. **No fear, no thrill.** We never sell danger and never wink at evasion. The reader should feel calmer after reading, not more paranoid.
4. **The phone-call register.** Borrow the vocabulary of calls, not chat apps: *the line, pick up, knock, hang up, on the line.* Never: *server, sync, cloud, encrypt-speak* in UI copy (the /security page is where the technical register lives).
5. **Short enough to read twice.** Confirmation copy is read under stress. One breath per sentence.

**Words we use:** line · knock · pick up · hang up · pair · **Nimna code** (the code's only name in UI — spec §2) · wipe · waits on your phone · gone.
**Words we avoid:** military-grade · unhackable · secret · spy · vault · shield · bulletproof · secure™ · anonymous (we're account-less, not anonymity tech — the spec is honest about IPs) · *pairing code* (spec-internal term, never UI) · *one-time / unlock / pay once / lifetime* (the model is a yearly subscription — always said with the permanence guarantee) · any price number (the store is the only place a price exists — spec §10).

## The strings

Strings 1–10 keep their original numbers (wireframe and screen annotations reference them); 11–18 are new with spec v0.1.1.

**1 · Onboarding — what it is**
> A private line between two people.
> No accounts. No cloud. Messages live on your two phones, nowhere else.

**2 · Onboarding — how pairing works**
> Pair once with a Nimna code you share however you like — read aloud, on paper, or as the QR shown right beside it.
> After that, the code is gone for good. The line is yours.

**3 · Onboarding — what we cannot see**
> We can't read your messages. We can't recover them either.
> There is nothing to hand over, because nothing is kept.

**4 · Empty channel list**
> No lines yet.
> Create a Nimna code, or enter one you've been given.

**5 · Peer offline (compose-to-outbox)**
> They're not on the line right now.
> Anything you write waits here — on your phone only — and goes through when you're both on.

**6 · Knock sent** *(the waiting state invites patience, never hammering — spec §4: the app never knocks twice on its own)*
> Knocked. If they pick up in the next minute, the line opens.
> One knock is enough — it won't repeat on its own.

**7 · Disappearing messages — the honor-system disclaimer** *(shown when setting a timer; the same timer governs photos and documents identically — spec §5.1)*
> Their app will delete this on schedule, and yours will too.
> A timer can't undo being read — a screenshot is still a screenshot. It's a courtesy between the two of you, not a guarantee.

**8 · Panic wipe confirmation** *(fast but unmistakable)*
> Wipe **everything**?
> Keys and messages are destroyed on this phone. There is no backup, anywhere, by design — nothing can bring them back.
> `[Wipe now]` `[Keep]`

**9 · Paywall** *(no number ever appears in copy — the paywall renders the store's localized price; designs carry `{STORE_PRICE}`. The permanence guarantee is headline, not fine print — spec §10)*
> One of you buys the line. The other never pays.
> One yearly subscription, as many lines as you care to create. Every line you make is yours for good — if the subscription lapses you keep them all, working exactly as before. A lapse only pauses making new ones.
> No account behind it. The receipt stays between you and the app store — we never learn who you are.
> `[{STORE_PRICE} — start]` `[Restore]`

**10 · Connection drops mid-session**
> The line dropped. Trying to reconnect…
> *(on recovery)* You're both here.

**11 · Screenshot disclosure — onboarding, as informed consent** *(first sentence is canonical from spec §5.2, verbatim)*
> Nimna can't stop a screenshot. It will always tell the other person.
> It only notices what happens inside the app — a second camera pointed at a screen is invisible to any software. Said up front, so you both know the terms.

**12 · Screenshot notice — the system line in the thread** *(bare centered caption, never a bubble; symmetric on both platforms)*
> They took a screenshot.
> *(own side)* You took a screenshot. They've been told.

**13 · Share-sheet briefing** *(canonical from spec §3.1, verbatim; rides every code share)*
> Works once, expires in 24h — share it like a password.

**14 · Sensitive content — the sender-side whisper** *(soft, non-blocking, at attach time; question is canonical from spec §5.3)*
> This looks like sensitive content — send anyway?
> `[Send anyway]` `[Go back]`

*Never blocks, never logs, never leaves the phone; neither side is ever told about the other's flags.*

**15 · Sensitive content — received, blurred** *(canonical from spec §5.3; on-device check after decryption, before display)*
> Sensitive content — tap to view.

*Tapping reveals. Nothing is reported to anyone, including the sender.*

**16 · Stale knock — the local hint** *(permitted UX sugar, spec §6.1; appears only after an extended unanswered stretch)*
> No answer in a while. If they lost their phone, this line can't come back — you'd pair again with a new code.

**17 · Attachments & media** *(spec §5.1)*
> *(attach, the metadata feature)* Photos are cleaned before they're sealed — location, device, and time are stripped on your phone, before encryption.
> *(compression default)* Sent smaller by default. Original quality is a toggle away.
> *(received media, export as deliberate act)* Nothing you receive touches your photo roll. It stays inside Nimna until you choose to take it out.
> *(over the cap)* That's over 5 MB — the line carries documents, not archives. Try a smaller file.

**18 · Push — the per-line toggle, off by default** *(channel settings; the honest one-line trade — spec §3.2.1)*
> Off: nothing about this line ever touches Apple or Google.
> On: a knock can wake this phone through their notification service, carrying two words — "New activity." No line, no name, no message — and the relay forgets the address the moment it's used.

## Register notes

- **Safety phrase is the closing ritual of pairing** (spec §3.1): "Call them and compare. Read these three words to each other. If they match, the line is yours alone." Two buttons only — *They match* / *They don't* — no skip affordance (USER 2026-07-04); the spec's "not enforced" is honored by the soft skip of tapping match.
- **The Nimna code renders as `XXX-XXX-XXX` everywhere** — mono face, three groups of three, hyphens included wherever it appears as text (spec §4: the grouping is part of the format).
- Buttons are verbs, one or two words: *Create a code · Enter a code · Knock · Pick up · Hang up · Wipe now · Keep · Send anyway · Go back.*
- Errors state what happened and what to do, never blame: "That code didn't match anything. Codes expire — ask them to make a new one." (Expired and never-existed are indistinguishable by design; failed pairing attempts never surface notifications — spec §3.1 silence doctrine.)
- **System lines** (screenshot notices, string 12) are bare centered captions in the thread — events, not speech; no bubble, no icon.
- The wipe pair `[Wipe now] [Keep]` is deliberate: the safe choice is a warm word, not "Cancel" — calm, not bureaucratic.

## Protocol honesty checklist (copy must never claim)

- ✗ "No one can ever see anything" → the relay sees IPs, timing, ciphertext sizes (spec §4).
- ✗ "Messages are deleted from the internet" → they were never *on* the internet at rest; say that instead.
- ✗ "Disappearing messages guarantee deletion" → honor-system (spec §5); string 7 is the canonical phrasing.
- ✗ "Fully anonymous" → account-less ≠ anonymous; never conflate.
- ✗ "Screenshots are blocked" or any prevention implication → detect-and-notify only (spec §5.2), and the notice itself is honor-system like expiry.
- ✗ Any price number, anywhere → the store shows the localized price; copy describes the model only (spec §10).
- ✗ "One-time" / "unlock" / "pay once" → yearly subscription, always stated with the permanence guarantee: lines created while subscribed work forever (spec §10).
- ✗ "Your lines come back when you resubscribe / reinstall" → only the subscription restores, via the store; lines die with the device, permanently, by design (spec §6.1).
- ✗ "We scan content" ambiguity → sensitive-content checks run on-device, after decryption, and can never phone home — nothing is blocked, logged, reported, or transmitted (spec §5.3).
- ✗ "We'll tell them you're waiting" or any presence promise → push is per-line opt-in, content-free ("New activity"), knock-triggered only; the relay keeps no token registry (spec §3.2).
