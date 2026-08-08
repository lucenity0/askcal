"""Gemini transport — AI Studio key or Vertex AI service account.

Lifted verbatim in behaviour from the old classify_batch body; the only change
is that it now returns raw text into the shared parser instead of relying on
response.parsed, so both providers take one code path. Under
response_mime_type="application/json" that text is the same JSON .parsed was
built from, so the constrained-decoding guarantee is not given up.
"""

from typing import Any

from app.config import get_settings
from app.llm.base import LLMResponse, LLMUnavailableError


class GeminiProvider:
    def __init__(self) -> None:
        s = get_settings()
        if not s.gemini_api_key and not s.gemini_use_vertex:
            raise LLMUnavailableError(
                "No Gemini backend configured — set ASKCAL_GEMINI_API_KEY, or "
                "ASKCAL_GEMINI_USE_VERTEX=true with ASKCAL_GEMINI_VERTEX_PROJECT."
            )
        self.model_name = s.gemini_model
        self.batch_size = s.classify_batch_size
        self.inter_batch_delay_seconds = s.classify_delay_seconds
        self._s = s

    async def complete(
        self, system: str, user: str, *, response_schema: Any | None = None
    ) -> LLMResponse:
        from google import genai  # deferred: import cost + optional dep at runtime

        s = self._s
        client = (
            genai.Client(
                vertexai=True,
                project=s.gemini_vertex_project,
                location=s.gemini_vertex_location,
            )
            if s.gemini_use_vertex
            else genai.Client(api_key=s.gemini_api_key)
        )
        config: dict = {"response_mime_type": "application/json"}
        if response_schema is not None:
            # Constrained decoding — Gemini's advantage over the CLI, kept.
            config["response_schema"] = response_schema

        response = await client.aio.models.generate_content(
            model=s.gemini_model,
            # Gemini has no separate system role in this call shape, so the two
            # halves are concatenated. The split exists for the CLI's
            # --system-prompt, and for prompt caching if an SDK provider lands.
            contents=f"{system}\n\n{user}",
            config=config,
        )
        usage = getattr(response, "usage_metadata", None)
        return LLMResponse(
            text=response.text or "",
            tokens_used=getattr(usage, "total_token_count", None),
        )
