"""Provider selection.

Deliberately not lru_cached: tests clear the settings cache between cases
(tests/test_classifier.py), and a memoised provider would outlive that and hand
back one built against stale settings. Construction is cheap — a shutil.which
once per sync pass costs nothing next to the LLM call it precedes.
"""

import logging

from app.config import get_settings
from app.llm.base import LLMProvider, LLMUnavailableError

logger = logging.getLogger("askcal.llm")


def build_provider() -> LLMProvider:
    """Construct the configured provider. Raises LLMUnavailableError if unusable."""
    if get_settings().llm_provider == "gemini":
        from app.llm.gemini import GeminiProvider

        return GeminiProvider()
    from app.llm.claude_code import ClaudeCodeProvider

    return ClaudeCodeProvider()


def provider_or_none() -> LLMProvider | None:
    """The provider, or None when it is simply not set up on this machine.

    Only LLMUnavailableError is swallowed — "not installed / not configured /
    no credentials" is a deployment state, not an error worth crashing a sync
    pass over. Anything else propagates.
    """
    try:
        return build_provider()
    except LLMUnavailableError as exc:
        logger.info(
            "LLM provider %r unavailable — skipping classification: %s",
            get_settings().llm_provider,
            exc,
        )
        return None


def classifier_configured() -> bool:
    """The single "can we classify at all?" predicate.

    Replaces the duplicated Gemini-shaped checks that used to sit in both
    classifier.py and sync.py, which had to be kept in step by hand and would
    both have gone stale the moment a second provider existed.
    """
    return provider_or_none() is not None
