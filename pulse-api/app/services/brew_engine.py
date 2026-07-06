"""Pulse brew engine — Python port of pulse-frontend/scripts/brew-engine.js.

The JS file is the single source of truth for brew selection. Keep the
thresholds, carry-forward penalty and task-count bump rules in sync with it.

Deliberately NOT ported: the color palettes. Colors live in brew-engine.js
(web, CSS variables) and BrewTheme.swift (iOS) — the API only ships
name / tagline / level per references/api-contracts.md, so it never becomes
a third source of truth for colors.

BREW SCALE (low → high stress):
    iced_latte → mocha → cappuccino → latte → long_black → espresso

REGRET SCORE: 0–100. Consequence of ignoring an item, not just urgency.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Literal

BrewKey = Literal["iced_latte", "mocha", "cappuccino", "latte", "long_black", "espresso"]
TempIndicator = Literal["hot", "warm", "iced"]


@dataclass(frozen=True)
class Brew:
    key: str
    name: str
    tagline: str
    level: str
    temp: str
    is_iced: bool


BREWS: dict[str, Brew] = {
    "espresso": Brew(
        "espresso", "ESPRESSO", "No BSing. Straight to the point.", "EXTREME", "HOT", False
    ),
    "long_black": Brew(
        "long_black", "LONG BLACK", "Bold. No room for distractions.", "HIGH", "HOT", False
    ),
    "latte": Brew(
        "latte", "LATTE", "Busy but manageable. You've got this.", "MED_HIGH", "HOT", False
    ),
    "cappuccino": Brew(
        "cappuccino", "CAPPUCCINO", "Balanced. Room to breathe.", "MEDIUM", "HOT", False
    ),
    "mocha": Brew(
        "mocha", "MOCHA", "Playful. A little chocolate, a little chill.", "MED_LOW", "WARM", False
    ),
    "iced_latte": Brew(
        "iced_latte", "ICED LATTE", "Chill day. Enjoy it while it lasts.", "LOW", "ICED", True
    ),
}

# Low → high stress
BREW_ORDER: list[BrewKey] = ["iced_latte", "mocha", "cappuccino", "latte", "long_black", "espresso"]

# The brew is determined by the HIGHEST scoring item + total load.
SCORE_THRESHOLDS: dict[str, int] = {
    "espresso": 85,  # ≥85: something critical today — deadline, OA, exam tomorrow
    "long_black": 65,  # ≥65: high consequence — placement deadline, client brief
    "latte": 45,  # ≥45: busy but manageable — assignments, 2-3 tasks
    "cappuccino": 25,  # ≥25: light — 1-2 tasks, nothing urgent
    "mocha": 10,  # ≥10: almost nothing — optional work only
    "iced_latte": 0,  # <10: nothing. free day.
}

# Even if no single item scores high, many medium items push the brew up.
TASK_COUNT_BUMP: dict[str, int] = {
    "latte": 6,  # 6+ tasks bumps anything below latte → latte
    "long_black": 10,  # 10+ tasks bumps anything below long_black → long_black
}

# Each task carried over from yesterday adds this to the highest item's score.
CARRY_FORWARD_PENALTY = 4


def calculate_brew(scores: Sequence[int | None], carry_forward: int = 0) -> BrewKey:
    """Port of calculateBrew({ items, carryForward }).

    The JS version takes items[{regretScore, track, title}] but only reads
    regretScore and the item count, so this takes the scores directly.
    """
    if not scores and carry_forward == 0:
        return "iced_latte"

    max_score = max((s or 0 for s in scores), default=0)
    effective = max_score + carry_forward * CARRY_FORWARD_PENALTY

    brew: BrewKey = "iced_latte"
    if effective >= SCORE_THRESHOLDS["espresso"]:
        brew = "espresso"
    elif effective >= SCORE_THRESHOLDS["long_black"]:
        brew = "long_black"
    elif effective >= SCORE_THRESHOLDS["latte"]:
        brew = "latte"
    elif effective >= SCORE_THRESHOLDS["cappuccino"]:
        brew = "cappuccino"
    elif effective >= SCORE_THRESHOLDS["mocha"]:
        brew = "mocha"

    # Task count bump (only bumps up, never down)
    task_count = len(scores)
    current_idx = BREW_ORDER.index(brew)
    if task_count >= TASK_COUNT_BUMP["long_black"] and current_idx < BREW_ORDER.index("long_black"):
        brew = "long_black"
    elif task_count >= TASK_COUNT_BUMP["latte"] and current_idx < BREW_ORDER.index("latte"):
        brew = "latte"

    return brew


def temp_for_score(score: int | None) -> TempIndicator:
    """Inbox temp indicator (🔴 hot / 🟡 warm / 🔵 iced) for a single item.

    Not defined in brew-engine.js; derived here from the brew that the item's
    score alone would land on, using that brew's temp (HOT/WARM/ICED).
    """
    brew = calculate_brew([score or 0])
    return {"HOT": "hot", "WARM": "warm", "ICED": "iced"}[BREWS[brew].temp]  # type: ignore[return-value]
