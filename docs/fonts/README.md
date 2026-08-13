# Fonts

Both faces are licensed and self-hosted. Nothing on the site is fetched from a
font CDN, which is what lets the page claim it loads nothing from anywhere else.

| file | family | licence |
|---|---|---|
| `elegancy-display.woff` | Elegancy — Sensatype Studio | licensed; `fsType 0`, embedding permitted |
| `blauernue-400/500/600.woff2` | Blauer Nue — Webhance Studio | licensed via Envato Elements; web use granted |

**Elegancy** is subset to the 89 glyphs the headings use — 9.5 KB rather than the
51 KB original. It is a display cut only and must stay on headings: it has no
italic (`italicAngle 0`, no swash set), so nothing may ask for one, or the
browser will shear the roman and produce a fake didone italic. It is also
missing `≤ ≥ →`, which belong to the mono voice anyway.

**Blauer Nue** ships as the foundry delivered it — their own WOFF2, not a
conversion. Their documentation includes a "Using Web Fonts" section instructing
exactly this. Only the three weights the page uses are here (400, 500, 600) and
no italic, because the page asks for none.

If either licence lapses or the page starts wanting a weight that is not here,
add the face rather than letting the browser synthesise it.
