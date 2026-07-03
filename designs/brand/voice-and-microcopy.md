# Nimna — Voice & Microcopy Guide (1.4)

## The voice

Nimna speaks like someone who has nothing to prove and nothing to hide. Plain words, short sentences, present tense. It states what the architecture does instead of promising what the company will do. It admits limits without flinching — honesty about the threat model is a brand asset, not a disclaimer to bury.

**Principles**

1. **Facts, not vows.** "Nothing is stored anywhere" — verifiable architecture. Never "we would never read your messages" — that's a promise about intent.
2. **Say the limit out loud.** Disappearing messages can't stop a screenshot. Say so, plainly, where the feature lives.
3. **No fear, no thrill.** We never sell danger and never wink at evasion. The reader should feel calmer after reading, not more paranoid.
4. **The phone-call register.** Borrow the vocabulary of calls, not chat apps: *the line, pick up, knock, hang up, on the line.* Never: *server, sync, cloud, encrypt-speak* in UI copy (the /security page is where the technical register lives).
5. **Short enough to read twice.** Confirmation copy is read under stress. One breath per sentence.

**Words we use:** line · knock · pick up · hang up · pair · code · wipe · waits on your phone · gone.
**Words we avoid:** military-grade · unhackable · secret · spy · vault · shield · bulletproof · secure™ · anonymous (we're account-less, not anonymity tech — the spec is honest about IPs).

## The 10 strings

**1 · Onboarding — what it is**
> A private line between two people.
> No accounts. No cloud. Messages live on your two phones, nowhere else.

**2 · Onboarding — how pairing works**
> Pair once with a code you share however you like — in person, on a call, on paper.
> After that, the code is gone for good. The line is yours.

**3 · Onboarding — what we cannot see**
> We can't read your messages. We can't recover them either.
> There is nothing to hand over, because nothing is kept.

**4 · Empty channel list**
> No lines yet.
> Create a code, or enter one you've been given.

**5 · Peer offline (compose-to-outbox)**
> They're not on the line right now.
> Anything you write waits here — on your phone only — and goes through when you're both on.

**6 · Knock sent**
> Knocked. If they pick up in the next minute, the line opens.

**7 · Disappearing messages — the honor-system disclaimer** *(shown when setting a timer)*
> Their app will delete this on schedule, and yours will too.
> A timer can't undo being read — a screenshot is still a screenshot. It's a courtesy between the two of you, not a guarantee.

**8 · Panic wipe confirmation** *(fast but unmistakable)*
> Wipe **everything**?
> Keys and messages are destroyed on this phone. There is no backup, anywhere, by design — nothing can bring them back.
> `[Wipe now]` `[Keep]`

**9 · Paywall**
> Creating a line is the only thing that costs. Pay once for as many as you like.
> No subscription. No account. The receipt stays between you and the app store — we never learn who you are.

**10 · Connection drops mid-session**
> The line dropped. Trying to reconnect…
> *(on recovery)* You're both here.

## Register notes

- **Safety phrase screen** uses the same register: "Read these three words to each other. If they match, the line is yours alone." (Full string set arrives with wireframes, F2/F3.)
- Buttons are verbs, one or two words: *Create a code · Enter a code · Knock · Pick up · Hang up · Wipe now · Keep.*
- Errors state what happened and what to do, never blame: "That code didn't match anything. Codes expire — ask them to make a new one."
- The wipe pair `[Wipe now] [Keep]` is deliberate: the safe choice is a warm word, not "Cancel" — calm, not bureaucratic.

## Protocol honesty checklist (copy must never claim)

- ✗ "No one can ever see anything" → the relay sees IPs, timing, ciphertext sizes (spec §4).
- ✗ "Messages are deleted from the internet" → they were never *on* the internet at rest; say that instead.
- ✗ "Disappearing messages guarantee deletion" → honor-system (spec §5); string 7 is the canonical phrasing.
- ✗ "Fully anonymous" → account-less ≠ anonymous; never conflate.
