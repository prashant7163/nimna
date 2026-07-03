# Nimna — Brand Directions (1.1)

Three distinct directions, each honoring the Brand Personality (calm, minimal, quiet luxury, discreet, warm) and respecting the Hard Avoids. A recommendation with reasoning follows at the end.

**Visual preview:** open [`direction-previews.html`](direction-previews.html) in a browser to see palettes, type, and motifs side by side.

---

## Direction A — "The Fine Object"
*Quiet luxury / analog object.*

**Mood.** A small, heavy, beautifully made thing. A watch dial read by lamplight. Hotel stationery with your name on it. A brass latch that closes with a soft click. The app is not software; it is an object you own.

**Adjectives.** Warm · weighted · unhurried · tactile · private.

**References.** A. Lange & Söhne dial typography; Braun ET66 calculator restraint; letterpress stationery; the felt lining of an instrument case; Aesop's brown-paper luxury.

**Color world.** Warm near-black with a brown undertone (espresso charcoal), ivory-paper text, hairline rules in **brass**. The live-session accent is **ember** — a coal, not an LED.
`#161310` surface · `#EDE7DC` text · `#C2A26B` brass · `#D9814E` ember (live).

**Type voice.** Fraunces (editorial serif, display only, ≥20pt) over Instrument Sans (all UI). Serif carries warmth; sans keeps the app quiet.

**Signature motif.** The hairline brass rule; engraved-plate moments — the pairing code presented like a serial number on a fine instrument.

**The rituals in this direction.** Code generation feels like engraving; the knock is a soft chime rendered as a brass glow; live session = a lamp lit at the top of the thread; panic wipe = the plate wiped blank.

**Sample line.** *"Nothing is kept. That is the luxury."*

**Risks.** Can drift ornamental or heritage-brand if undisciplined; serif must never appear at UI sizes. Least distinctive of the three — quiet luxury is a crowded aesthetic.

---

## Direction B — "Deep Water"
*Sanskrit-rooted minimalism, from the etymology itself.*

**Mood.** *Nimna* (निम्न): low ground — the place water gathers. Ink poured into still water; a pond at night; depth as safety. What sinks is held; the surface tells you nothing. The brand goes literally downward: calm, deep, settled.

**Adjectives.** Deep · still · inky · settled · unreadable (from the outside).

**References.** Sumi-e ink wash; Rothko's blue-blacks; the Devanagari *shirorekha* (headstroke) abstracted into a waterline; night water photography.

**Color world.** Ink indigo-black, moon-grey text, and a single **lamp-gold** accent — a diya flame on dark water. The knock is a ripple ring; live is the flame held steady.
`#0C1017` surface · `#DDE3EA` text · `#E3B34C` lamp gold · ripple rings in `#3D4A5C`.

**Type voice.** Martel (display serif designed with Devanagari scholarship) over Mukta (UI sans, a genuine Latin + Devanagari family). The type system literally shares heritage with the name — the most honest execution of the etymology possible without a single decorative Devanagari glyph.

**Signature motif.** The horizontal waterline; concentric ripple rings; depth gradients (never decoration — always meaning: things that disappear *sink*).

**The rituals in this direction.** Pairing = two ripples meeting; disappearing messages drift down and dissolve; the wipe = the pond goes perfectly still.

**Sample line.** *"Said, then gone. Like a stone into deep water."*

**Risks.** Water/stillness vocabulary sits near "meditation app" — held off by strict geometry and zero softness in layout. Cultural motifs must stay abstract and respectful; no literal iconography, ever.

---

## Direction C — "The Line"
*The positioning line made visible.*

**Mood.** One warm filament of light in a dark room. A landline for two people who mean it. Everything is monochrome and still — except the line, which is alive only when you both are. Not a network, not a cloud: a line, with a person at each end.

**Adjectives.** Direct · taut · luminous · spare · honest.

**References.** Dieter Rams — as little as possible, but warm; a tin-can telephone drawn as a single stroke; an incandescent filament; the red phone reimagined as one amber line.

**Color world.** True neutral near-black, quiet greys, and one **incandescent amber** accent. The color system is a status language, mapped 1:1 to the protocol: dotted grey line = offline · breathing amber = knocking · solid lit amber = live · line cut = wiped.
`#0B0B0C` surface · `#E8E6E1` text · `#F2A65A` incandescent (live/knock) · `#5A5A5E` line-idle.

**Type voice.** Schibsted Grotesk, one family for everything — display to caption. Restraint as identity; warmth carried by amber, spacing, and the writing. Tabular numerals for pairing codes.

**Signature motif.** THE line. The wordmark rests on it; the chat screen carries it as the live session indicator; the website hero is two points and the line between them, vanishing when broken. Used only where it means something (session state, brand moments) — never as decoration.

**The rituals in this direction.** They aren't illustrated — they *are* the motif. Knock → the line pulses. Accept → it connects and lights. Hangup → it dims to dots. Panic wipe → the line is cut. The protocol's state machine is the brand's animation language.

**Sample line.** *"One line. Two people. Nothing else."*

**Risks.** Austerity can tip into coldness — countered with warm amber, generous line-height, and humane microcopy. The single motif must be rationed or it becomes a gimmick.

---

## Recommendation: Direction C — "The Line"

**Reasoning.**

1. **The architecture is the brand — literally.** C is the only direction whose core motif is also the product's state machine. Offline / knocking / live / wiped are protocol phases, and the line renders them without a single invented metaphor. Every other direction decorates the protocol; this one *draws* it.
2. **Ownable.** Quiet luxury (A) is a crowded aesthetic; water-calm (B) borders other categories. No messenger owns "the line," yet the line is already in Nimna's positioning sentence.
3. **It survives everywhere.** One stroke works at 48px on a home screen (discreet, per the icon decision), as a favicon, as a hero animation, in mono, embossed on nothing.
4. **Discretion is native to it.** A near-black icon with a short amber line is exactly "unremarkable outside, premium inside."

**Runner-up:** A — and C deliberately borrows its temperature: the amber is incandescent (a filament, a lamp), not a signal LED. If C feels too spare after the checkpoint, folding A's ivory warmth into C's palette is a low-cost hybrid.

**Protocol check.** No direction implies stored history, identity, or asynchronous delivery. B's "sinking" disappearing-messages animation must still carry the honor-system disclaimer (spec §5). C's line-states map exactly to spec §3.2–3.4.
