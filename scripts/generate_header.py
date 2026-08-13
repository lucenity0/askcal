#!/usr/bin/env python3
"""Regenerate Askcal's README header and section divider.

  python3 scripts/generate_header.py          -> assets/header.svg, assets/divider.svg
  python3 scripts/generate_header.py verify   -> assets/header_verify.svg (static
                                                 frame, for eyeballing the layout)

Same construction as the profile and Liffy headers: hand-built self-contained
SVG, no images, no external fonts, no third-party services. Animation is CSS
@keyframes gated behind prefers-reduced-motion, so everything that matters is
readable without motion — which is also what makes it safe on GitHub, where
scripts never run and only a subset of CSS survives.

The palette is the app's own — warm paper, a red margin rule — rather than the
profile's greys. The two read as one product that way, which is the same
argument that got the launch screen rebuilt. Swapping back is the PALETTE block
below and nothing else.
"""
import os
import sys

# ---- CONFIG ---------------------------------------------------------------
NAME = "Askcal"
HANDLE = "@lucenity0/askcal"
QUALIFIER = "iOS · FastAPI"
SUBTITLE = "your inbox, ranked by regret."
CHIPS = ["SWIFTUI", "FASTAPI", "CLAUDE"]
KICKER = "// ASKCAL · GMAIL → YOUR DAY"
STATUS = "SYNCING"
COMMAND = "> askcal today"
FOOTER = "~ $ 3 done · 1 moved on"

# The day drawn on the right-hand page: (time, label, done)
ENTRIES = [
    ("09:00", "assignment due", True),
    ("11:30", "reply to prof", True),
    ("14:00", "client brief", False),
    ("17:00", "semester fees", False),
    ("21:00", "close the day", False),
]

# ---- PALETTE (app's own; see Askcal/DesignSystem/Paper.swift) --------------
PAPER = "#F5F0E6"
RULE = "#CFC5AE"
RULE_STRONG = "#B3A98F"
INK = "#2A2724"
INK_DIM = "#57514A"
INK_SUB = "#6E675E"
MARGIN = "#B4654A"  # the red margin line — the one accent in the whole app
# ---------------------------------------------------------------------------

VERIFY = len(sys.argv) > 1 and sys.argv[1] == "verify"
W, H = 880, 300


def esc(s: str) -> str:
    """Only what breaks XML, plus the punctuation this file actually uses.

    Written as entities rather than raw bytes so the SVG renders identically
    however GitHub decides to serve it.
    """
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&#62;")
        .replace("·", "&#183;")
        .replace("—", "&#8212;")
        .replace("→", "&#8594;")
        .replace("'", "&#39;")
    )


def header() -> str:
    out = []
    a = out.append

    a(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
        f'width="{W}" height="{H}" '
        f"font-family=\"'Courier New', ui-monospace, monospace\" role=\"img\" "
        f'aria-label="{esc(NAME)} — {esc(SUBTITLE)}">'
    )

    a("<defs>")
    if VERIFY:
        a("<style>.px{opacity:1}.scan{opacity:0}.boot{opacity:1}</style>")
    else:
        a("""<style>
  .tick { opacity: 0; }
  .scan { opacity: 0; }
  @keyframes fadein { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }
  @keyframes blink  { 0%,49% { opacity: 1 } 50%,100% { opacity: 0 } }
  @keyframes dot    { 0%,60% { opacity: 1 } 70%,100% { opacity: .15 } }
  @keyframes check  { 0%,12% { opacity: 0 } 22%,88% { opacity: 1 } 96%,100% { opacity: 0 } }
  @keyframes scan   { 0% { transform: translateY(0); opacity: 0 } 12% { opacity: .10 } 88% { opacity: .10 } 100% { transform: translateY(224px); opacity: 0 } }
  @media (prefers-reduced-motion: no-preference) {
    .boot { opacity: 0; transform-box: fill-box; animation: fadein .6s ease forwards; }
    .d1 { animation-delay: .10s } .d2 { animation-delay: .30s } .d3 { animation-delay: .50s }
    .d4 { animation-delay: .70s } .d5 { animation-delay: .90s }
    .cursor { animation: blink 1s steps(1) infinite; }
    .odot   { animation: dot 1.8s ease-in-out infinite; }
    .tick   { animation: check 6s ease-in-out infinite; }
    .scan   { animation: scan 4.8s linear infinite; }
  }
</style>""")
    a("</defs>")

    # The page itself.
    a(
        f'<rect x="4" y="4" width="{W - 8}" height="{H - 8}" rx="18" '
        f'fill="{PAPER}" stroke="{INK}" stroke-width="4"/>'
    )

    # Ruled paper, not a grid: horizontal rules only, the way a page is ruled.
    a(f'<g stroke="{RULE}" stroke-width="1">')
    for y in range(60, H - 20, 28):
        a(f'<line x1="20" y1="{y}" x2="{W - 20}" y2="{y}"/>')
    a("</g>")

    # The margin rule. One vertical red line, the only colour in the app.
    a(f'<line x1="44" y1="20" x2="44" y2="{H - 20}" stroke="{MARGIN}" stroke-width="2" opacity="0.7"/>')

    def bracket(x, y, dx, dy):
        length = 16
        a(
            f'<path d="M {x + dx * length} {y} L {x} {y} L {x} {y + dy * length}" '
            f'fill="none" stroke="{INK}" stroke-width="3"/>'
        )

    bracket(26, 26, 1, 1)
    bracket(W - 26, 26, -1, 1)
    bracket(26, H - 26, 1, -1)
    bracket(W - 26, H - 26, -1, -1)

    a(f'<text x="62" y="46" font-size="12" letter-spacing="3" fill="{INK_SUB}">{esc(KICKER)}</text>')
    # Left-anchored deliberately. `text-anchor="end"` plus letter-spacing is
    # handled inconsistently across renderers — one of them dropped the word off
    # the canvas entirely — and a fixed x with room to spare cannot.
    a(f'<circle class="odot" cx="{W - 190}" cy="42" r="5" fill="{MARGIN}"/>')
    a(f'<text x="{W - 176}" y="46" font-size="10" letter-spacing="3" fill="{INK_SUB}">{STATUS}</text>')

    a(f'<text class="boot d1" x="62" y="96" font-size="15" letter-spacing="1" fill="{INK_SUB}">{esc(COMMAND)}</text>')
    a(f'<text class="boot d1" x="60" y="152" font-size="58" font-weight="700" letter-spacing="1" fill="{INK}">{NAME}</text>')
    # Trailing text rides in the same <text> as a tspan, so the renderer places
    # it after whatever the previous run actually measured. Positioning these by
    # multiplying a character count by a guessed advance put "iOS" inside
    # "askcal" the moment a fallback font was a hair wider than Courier.
    a(
        f'<text class="boot d2" x="63" y="186" font-size="19" font-weight="700" '
        f'letter-spacing="1" fill="{INK}">{esc(HANDLE)}'
        f'<tspan font-size="13" font-weight="400" fill="{INK_SUB}" dx="14">'
        f'{esc(QUALIFIER)}</tspan></text>'
    )

    a(
        f'<text class="boot d3" x="64" y="216" font-size="14" letter-spacing=".5" '
        f'fill="{INK_DIM}">{esc(SUBTITLE)}'
        f'<tspan class="cursor" dx="6" fill="{INK}">&#9608;</tspan></text>'
    )

    cx = 62
    for chip in CHIPS:
        w = 20 + len(chip) * 8
        a('<g class="boot d4">')
        a(
            f'<rect x="{cx}" y="240" width="{w}" height="24" rx="3" fill="none" '
            f'stroke="{INK}" stroke-width="1.5"/>'
        )
        a(
            f'<text x="{cx + w / 2:.0f}" y="256" font-size="11" letter-spacing="2" '
            f'fill="{INK}" text-anchor="middle">{chip}</text>'
        )
        a("</g>")
        cx += w + 12

    # The right-hand page: a day, drawn the way the app draws one.
    px, py = 560, 74
    a(f'<text x="{px}" y="{py - 16}" font-size="10" letter-spacing="2" fill="{INK_SUB}">// TODAY</text>')

    for i, (time, label, done) in enumerate(ENTRIES):
        y = py + i * 34
        a(f'<text x="{px}" y="{y + 5}" font-size="11" fill="{INK_SUB}">{time}</text>')

        mark_x = px + 52
        a(
            f'<circle cx="{mark_x}" cy="{y}" r="9" fill="{INK if done else "none"}" '
            f'stroke="{INK if done else RULE_STRONG}" stroke-width="2"/>'
        )
        if done:
            # The tick is its own element so it can animate in: the page fills
            # itself out over the loop, which is the one thing this app does.
            cls = "" if VERIFY else f' class="tick" style="animation-delay:{1.0 + i * 0.5:.1f}s"'
            a(
                f'<path{cls} d="M {mark_x - 4} {y} L {mark_x - 1} {y + 3.5} '
                f'L {mark_x + 4.5} {y - 3.5}" fill="none" stroke="{PAPER}" '
                f'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
            )

        a(
            f'<text x="{mark_x + 20}" y="{y + 5}" font-size="13" '
            f'fill="{INK_SUB if done else INK}">{esc(label)}</text>'
        )
        if done:
            # Struck through, exactly as a finished row reads in the app.
            width = len(label) * 7.0
            a(
                f'<line x1="{mark_x + 20}" y1="{y + 1}" x2="{mark_x + 20 + width:.0f}" '
                f'y2="{y + 1}" stroke="{INK_SUB}" stroke-width="1.2"/>'
            )

    a(
        f'<text x="{px}" y="{py + len(ENTRIES) * 34 + 8}" font-size="11" '
        f'letter-spacing="1" fill="{INK_SUB}">{esc(FOOTER)}</text>'
    )

    if VERIFY:
        a(f'<rect x="26" y="150" width="{W - 52}" height="2" fill="{INK}" opacity="0.10"/>')
    else:
        a(f'<rect class="scan" x="26" y="40" width="{W - 52}" height="2" fill="{INK}"/>')
    a("</svg>")
    return "\n".join(out)


def divider() -> str:
    """A ruled line with a mark travelling along it — a pen crossing the page."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 880 22" width="880" height="22" font-family="'Courier New', ui-monospace, monospace" role="img" aria-label="section divider">
  <defs>
    <style>
      .mark {{ opacity: .18; }}
      @keyframes slide {{ 0% {{ transform: translateX(0); opacity:.9 }} 92% {{ opacity:.9 }} 100% {{ transform: translateX(848px); opacity:.9 }} }}
      @media (prefers-reduced-motion: no-preference) {{
        .mark {{ opacity: .9; animation: slide 3.6s linear infinite; }}
      }}
    </style>
  </defs>
  <line x1="8" y1="11" x2="872" y2="11" stroke="{RULE}" stroke-width="2" stroke-dasharray="2 6"/>
  <line x1="8" y1="4" x2="8" y2="18" stroke="{RULE_STRONG}" stroke-width="2"/>
  <line x1="872" y1="4" x2="872" y2="18" stroke="{RULE_STRONG}" stroke-width="2"/>
  <rect class="mark" x="8" y="7" width="14" height="8" rx="2" fill="{MARGIN}"/>
</svg>"""


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets = os.path.join(root, "assets")
    os.makedirs(assets, exist_ok=True)

    name = "header_verify.svg" if VERIFY else "header.svg"
    with open(os.path.join(assets, name), "w") as f:
        f.write(header())
    print("wrote", os.path.join("assets", name))

    if not VERIFY:
        with open(os.path.join(assets, "divider.svg"), "w") as f:
            f.write(divider())
        print("wrote", os.path.join("assets", "divider.svg"))
