# pulse-landing

`pulse.lucenity.dev` — scroll-driven WebGL landing experience. Not a product
page, an experience.

Single HTML file, zero build step. Three.js r128 + GSAP ScrollTrigger from CDN.

## Run locally

Any static server works:

```bash
python3 -m http.server 4173 -d pulse-landing
# → http://localhost:4173
```

## The journey

One scroll-progress float (0→1 across a 780vh spacer) drives the story on a
fixed canvas:

| Progress | Scene |
|----------|-------|
| 0.00–0.13 | **The Bean** — procedural bean (canvas roast texture, bump map, crease with lip, contact shadow), scales in |
| 0.13–0.26 | **The Crack** — bean splits (clipped halves), ~3000 instanced roast-brown grounds burst out |
| 0.26–0.44 | **The Tamp** — grounds vortex into the portafilter basket and compress into a puck; group head + portafilter assemble |
| 0.44–0.62 | **The Pull** — twin liquid espresso streams (wobble + sheen shader) fill a ceramic cup below |
| 0.64–1.00 | **The Orders** — camera tilts down; the same cup morphs through espresso → long black → latte → cappuccino → mocha, then crossfades to the iced-latte glass (pour-gradient liquid + ice cubes) as the right-side board cycles |

Then a normal-flow CTA section: waitlist (client-side stub) with a pour
animation on submit — stream fills a cup outline, steam, confirmation line.

## Motion exceptions (owner-approved)

`landing-motion.md` says scroll-driven only; per Nafees' direction these run
on their own clock, all gated behind `prefers-reduced-motion`:
- the hero PULSE wordmark heartbeat (`pulse-beat`)
- steam drift above hot brews
- the iced-latte gradient bleed

## Dev hook

`/?p=0.42` pins the journey at a fixed progress — handy for reviewing or
demoing a single scene without scrubbing.

## Source-of-truth notes

- Colors (brew accents, pour gradient stops) come from
  `pulse-frontend/scripts/brew-engine.js` — don't invent new ones.
- Grain + VHS glitch CSS are verbatim from
  `pulse-motion/references/landing-motion.md` (defined once, never redefined).
- Light editorial tokens (System 3) only — never the app's dark brew tokens.
- All motion is scroll-driven except the VHS glitch (fires once on load, per
  spec). `prefers-reduced-motion` disables the glitch, reveal transitions,
  and scroll smoothing.
- Three.js is pinned at r128 per the spec — mind the API surface
  (e.g. `Vector3.randomDirection()` doesn't exist yet in r128).

## Known limitations

- Waitlist form is a client-side stub — shows the success line, stores
  nothing. Wire to a real endpoint (or Formspree/Buttondown) before launch.
- No `CNAME`/deploy config yet — GitHub Pages setup comes at deploy time.
