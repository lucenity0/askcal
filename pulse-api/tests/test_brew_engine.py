"""Parity tests against pulse-frontend/scripts/brew-engine.js (calculateBrew).

Every case here mirrors the JS behavior exactly. If one of these fails after
an edit, the Python port has drifted from the source of truth.
"""

import pytest

from app.services.brew_engine import BREW_ORDER, BREWS, calculate_brew, temp_for_score


def test_no_items_no_carry_is_iced_latte():
    assert calculate_brew([]) == "iced_latte"


@pytest.mark.parametrize(
    ("score", "expected"),
    [
        (100, "espresso"),
        (85, "espresso"),  # threshold boundary
        (84, "long_black"),
        (65, "long_black"),
        (64, "latte"),
        (45, "latte"),
        (44, "cappuccino"),
        (25, "cappuccino"),
        (24, "mocha"),
        (10, "mocha"),
        (9, "iced_latte"),
        (0, "iced_latte"),
    ],
)
def test_score_thresholds(score, expected):
    assert calculate_brew([score]) == expected


def test_highest_item_wins():
    assert calculate_brew([10, 30, 90]) == "espresso"


def test_carry_forward_penalty_adds_4_per_task():
    # 60 + 2*4 = 68 → long_black
    assert calculate_brew([60], carry_forward=2) == "long_black"
    # 60 + 1*4 = 64 → still latte
    assert calculate_brew([60], carry_forward=1) == "latte"


def test_carry_forward_only_no_items():
    # JS: maxScore=0, effective = 3*4 = 12 → mocha
    assert calculate_brew([], carry_forward=3) == "mocha"
    # 1*4 = 4 < 10 → iced_latte
    assert calculate_brew([], carry_forward=1) == "iced_latte"


def test_task_count_bump_to_latte():
    # 6 medium tasks: max 30 → cappuccino, bumped to latte by count
    assert calculate_brew([30] * 6) == "latte"
    # 5 tasks: no bump
    assert calculate_brew([30] * 5) == "cappuccino"


def test_task_count_bump_to_long_black():
    # 10 tasks at latte level → long_black
    assert calculate_brew([50] * 10) == "long_black"


def test_bump_never_downgrades():
    # espresso stays espresso even with 12 tasks
    assert calculate_brew([90] * 12) == "espresso"
    # long_black at 10+ tasks stays long_black (idx not < long_black)
    assert calculate_brew([70] * 10) == "long_black"


def test_none_scores_treated_as_zero():
    # JS: i.regretScore ?? 0
    assert calculate_brew([None, None]) == "iced_latte"
    assert calculate_brew([None, 50]) == "latte"


def test_brew_order_matches_js():
    assert BREW_ORDER == ["iced_latte", "mocha", "cappuccino", "latte", "long_black", "espresso"]
    assert set(BREWS) == set(BREW_ORDER)


def test_brew_metadata_matches_js():
    assert BREWS["espresso"].level == "EXTREME"
    assert BREWS["long_black"].level == "HIGH"
    assert BREWS["latte"].level == "MED_HIGH"
    assert BREWS["cappuccino"].level == "MEDIUM"
    assert BREWS["mocha"].level == "MED_LOW"
    assert BREWS["iced_latte"].level == "LOW"
    assert BREWS["iced_latte"].is_iced
    assert not any(BREWS[k].is_iced for k in BREWS if k != "iced_latte")


@pytest.mark.parametrize(
    ("score", "expected"),
    [
        (88, "hot"),  # espresso → HOT
        (50, "hot"),  # latte → HOT
        (30, "hot"),  # cappuccino → HOT
        (15, "warm"),  # mocha → WARM
        (5, "iced"),  # iced_latte → ICED
        (None, "iced"),
    ],
)
def test_temp_indicator(score, expected):
    assert temp_for_score(score) == expected
