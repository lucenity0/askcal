"""Provider-agnostic LLM transport contract.

The port is deliberately dumb: a provider turns (system, user) into text.
Everything that knows what Askcal is *asking* — the classifier prompt, the JSON
schema, reconciliation by gmail_id — lives one layer up in
app/services/classifier.py, so adding a provider can never fork the prompt.

That prompt is tuned (the finance rule, digest-vs-opportunity, the explicit
"a no-reply sender does NOT lower action_required" clause) and its consequences
are pinned by tests/test_auto_task.py. A `classify()`-shaped port would hand
each provider its own copy and the next tuning pass would either be applied
twice or leave the providers silently disagreeing about what an invoice is.
"""

from dataclasses import dataclass
from typing import Any, Protocol, runtime_checkable


@dataclass(slots=True)
class LLMResponse:
    text: str
    # None means UNKNOWN, never zero. A provider that cannot report usage has to
    # say so — a 0 reads as "this classification was free", which would under-
    # report subscription burn by an order of magnitude in the sync log.
    tokens_used: int | None = None


@runtime_checkable
class LLMProvider(Protocol):
    """A transport. Constructing one must fail loudly if it cannot be used."""

    model_name: str

    # Pacing belongs to the provider's economics, not to Askcal.
    # Gemini free tier: small batches, sleep between them (RPM limited).
    # Claude Code: one bigger call beats several small ones — every invocation
    # re-pays the CLI's own multi-thousand-token preamble against subscription
    # quota, and there is no per-minute request limit to pace against.
    batch_size: int
    inter_batch_delay_seconds: float

    async def complete(
        self,
        system: str,
        user: str,
        *,
        response_schema: Any | None = None,
    ) -> LLMResponse:
        """Return the model's text.

        ``response_schema`` is an *optional capability hint*: a provider with
        constrained decoding (Gemini) should use it; one without (the Claude
        Code CLI) must ignore it. It is never the only thing holding the output
        in shape — app/llm/structured.py renders the same schema into ``system``
        for every provider, from one source of truth.
        """
        ...


class LLMError(RuntimeError):
    """Base for every failure a provider can report."""


class LLMUnavailableError(LLMError):
    """The provider cannot be used at all: not installed, not configured.

    Raised at CONSTRUCTION, so a misconfiguration surfaces before a sync pass
    starts rather than forty seconds into one.
    """


class LLMAuthError(LLMUnavailableError):
    """Installed but holding no usable credentials.

    Subclasses Unavailable deliberately: classifier_configured() should report
    False for a missing token exactly as it does for a missing binary.
    """


class LLMLimitError(LLMError):
    """The subscription's own rate limit or quota was reached.

    Its own class because it is the one failure that is neither a bug nor a
    misconfiguration — nothing is wrong and waiting fixes it. sync.py uses it to
    stop the pass instead of grinding the remaining chunks against a wall.
    """
