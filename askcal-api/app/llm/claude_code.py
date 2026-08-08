"""Claude Code CLI as a completion endpoint.

Authenticates with the owner's own Claude subscription, so Askcal classifies
mail with credentials that already exist and no metered API key at all.

Async throughout, and that is not a style choice. Askcal's whole pipeline is
asyncio: the sync loop runs in the FastAPI lifespan (app/main.py) inside the
single uvicorn worker that also serves HTTP (docker-entrypoint.sh pins
--workers 1 because the loop is in-process). A blocking subprocess.run here
would freeze every API request for the length of a classification.

Most of the specifics below exist because they broke first in Liffy, where this
pattern originated. They are load-bearing, not defensive.
"""

import asyncio
import contextlib
import json
import logging
import os
import shutil
import tempfile
from typing import Any

from app.config import get_settings
from app.llm.base import (
    LLMAuthError,
    LLMError,
    LLMLimitError,
    LLMResponse,
    LLMUnavailableError,
)

logger = logging.getLogger("askcal.llm.claude_code")

# Matched case-insensitively against the CLI's own output BEFORE any attempt to
# parse it, because a rate-limited run exits nonzero with prose where JSON goes.
# Telling a hit limit apart from a crash is the difference between "wait" and
# "something is broken".
_LIMIT_MARKERS = (
    "rate limit",
    "usage limit",
    "quota",
    "too many requests",
    "429",
    "resets at",
)
_AUTH_MARKERS = (
    "not logged in",
    "not authenticated",
    "please run /login",
    "please log in",
    "invalid api key",
    "oauth token has expired",
    "authentication_error",
)

# Must never reach the child. The CLI silently PREFERS an API key over the
# subscription credential when it sees both, so an inherited ANTHROPIC_API_KEY
# means every classification that looked like it rode the subscription was
# billed to Console credits instead — and nothing surfaces it, because the calls
# succeed. ANTHROPIC_BASE_URL goes too: an inherited base URL aims the CLI
# somewhere its credentials mean nothing.
_ANTHROPIC_API_VARS = ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL")


def running_in_container() -> bool:
    """True inside Docker/Kubernetes.

    Load-bearing: on a dev machine the CLI reads ~/.claude and needs nothing
    configured, but in a container there is no such home directory and an OAuth
    token is mandatory. Askcal's production image is exactly that case.
    """
    if os.path.exists("/.dockerenv"):
        return True
    try:
        with open("/proc/1/cgroup", encoding="utf-8") as fh:
            return any(m in fh.read() for m in ("docker", "kubepods", "containerd"))
    except OSError:
        return False  # no /proc — macOS, so not a Linux container


class ClaudeCodeProvider:
    # An empty ALLOW-list, not a deny-list. The deny-list this replaces named
    # thirteen tools and still missed `ReportFindings`, which the model reaches
    # for precisely when the prompt looks like a classification or review task:
    # it filed its answer through the tool and wrote prose about it, leaving no
    # JSON anywhere in the transcript. Enumerating built-ins only has to be out
    # of date once. `--tools ""` is the CLI's own "disable all tools".
    _NO_TOOLS = ""

    def __init__(self) -> None:
        s = get_settings()
        self.model_name = s.claude_code_model
        self.batch_size = s.claude_code_batch_size
        self.inter_batch_delay_seconds = s.claude_code_delay_seconds
        self._binary = s.claude_code_binary
        self._effort = s.claude_code_effort
        self._timeout = s.claude_code_timeout_seconds
        self._token = s.claude_code_oauth_token

        # Both checks at CONSTRUCTION. The whole point is that a misconfigured
        # provider fails where someone is watching — at startup preflight or the
        # top of a sync pass — not as a subprocess error buried mid-classification.
        if shutil.which(self._binary) is None:
            raise LLMUnavailableError(
                f"{self._binary!r} is not on PATH. Install Claude Code and sign in, "
                f"or set ASKCAL_LLM_PROVIDER=gemini."
            )
        if running_in_container() and not self._token:
            raise LLMAuthError(
                "ASKCAL_LLM_PROVIDER=claude_code is running inside a container, "
                "where there is no home directory holding Claude credentials. Run "
                "`claude setup-token` on the host and set "
                "ASKCAL_CLAUDE_CODE_OAUTH_TOKEN in .env.prod."
            )

    def _argv(self, system: str) -> list[str]:
        # The user prompt goes on STDIN, never in here. As an argv element it
        # hits `[Errno 7] Argument list too long` on real payloads — a batch of
        # 25 emails at EXCERPT_CHARS=1500 is 15-40KB, which is exactly the size
        # this provider exists to handle.
        return [
            self._binary,
            "--print",
            # NOT "json", which returns only the CLI's final assistant turn.
            # Claude Code is an agent loop and takes more than one turn even with
            # every tool disabled: turn 1 the answer, turn 2 a human-facing
            # summary. "json" hands back turn 2, the classification is discarded
            # unseen, and it surfaces as the misleading "no JSON found". The full
            # transcript has the answer in it, so read the transcript.
            # --verbose is not optional; the CLI rejects the combination without it.
            "--output-format",
            "stream-json",
            "--verbose",
            "--effort",
            self._effort,
            # REPLACES the CLI's own system prompt rather than appending to it.
            # Appending would stack Askcal's classifier persona on top of the
            # coding-agent persona and pay quota for both.
            "--system-prompt",
            system,
            # Keep --tools immediately before another flag: it is variadic
            # (`--tools <tools...>`), so a trailing empty value would swallow
            # whatever came after it.
            "--tools",
            self._NO_TOOLS,
            "--model",
            self.model_name,
        ]

    def _env(self) -> dict[str, str]:
        """The child environment: ours, minus the API keys, plus the token.

        Stripping is the load-bearing half. PATH is inherited deliberately —
        the CLI is a node script and cannot find node without it.
        """
        env = {k: v for k, v in os.environ.items() if k not in _ANTHROPIC_API_VARS}
        if self._token:
            env["CLAUDE_CODE_OAUTH_TOKEN"] = self._token
        # Email bodies are already leaving the process; don't also ship
        # telemetry about the run.
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        return env

    async def complete(
        self, system: str, user: str, *, response_schema: Any | None = None
    ) -> LLMResponse:
        # response_schema is ignored: the CLI has no constrained-decoding flag.
        # The schema still reaches the model — structured.py renders it into
        # `system` for every provider.

        # A neutral empty directory, not the repo. Claude Code reads CLAUDE.md
        # and picks up ambient file context from its working directory, so
        # running it inside askcal-api would leak the codebase into an
        # email-classification prompt: more quota spent, worse results.
        with tempfile.TemporaryDirectory(prefix="askcal-classify-") as workdir:
            proc = await asyncio.create_subprocess_exec(
                *self._argv(system),
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=workdir,
                env=self._env(),
            )
            try:
                # communicate(), not manual reads: a stream-json transcript for a
                # 25-email batch is tens of KB, and writing stdin without draining
                # stdout deadlocks on the OS pipe buffer.
                out_b, err_b = await asyncio.wait_for(
                    proc.communicate(user.encode()), timeout=self._timeout
                )
            except (asyncio.TimeoutError, TimeoutError):
                # wait_for cancels communicate() but does NOT reap the child.
                # Without this kill a wedged `claude` survives for the container's
                # lifetime, keeps burning quota, and outlives the temp directory
                # the `with` is about to delete.
                proc.kill()
                with contextlib.suppress(ProcessLookupError):
                    await proc.wait()
                raise LLMError(f"Claude Code timed out after {self._timeout}s") from None

        stdout = out_b.decode(errors="replace")
        stderr = err_b.decode(errors="replace")

        if proc.returncode != 0:
            # Log in full before truncating — the subprocess output is gone the
            # moment this returns.
            logger.error(
                "Claude Code exited %s\n--- stderr ---\n%s\n--- stdout ---\n%s",
                proc.returncode,
                stderr or "(empty)",
                stdout or "(empty)",
            )
            raise _classify_failure(proc.returncode, _failure_blob(stdout, stderr))

        payload, turns, tools = _parse_stream(stdout)
        if payload is None:
            raise LLMError(
                f"Claude Code did not return a transcript: {stdout.strip()[:300]!r}"
            )
        if payload.get("is_error") or payload.get("subtype") != "success":
            # A limit can also arrive as a CLEAN exit with an error payload, so
            # the same classification applies here as to a nonzero exit.
            raise _classify_failure(0, json.dumps(payload))

        # Last assistant turn that actually carries JSON — object OR array,
        # because Askcal's answer is a list of N signal objects, not one object.
        text = next(
            (t for t in reversed(turns) if _looks_like_json(t)),
            payload.get("result") or "",
        )
        if not text:
            raise LLMError(
                f"Claude Code returned no result (stop_reason={payload.get('stop_reason')})"
            )
        if tools and not _looks_like_json(text):
            # A tool call means the answer went somewhere unreadable and the text
            # is a summary of it. Naming the tool is what makes this a one-line
            # diagnosis instead of an afternoon reading session transcripts.
            raise LLMError(
                f"Claude Code answered by calling {', '.join(sorted(set(tools)))} "
                f"instead of returning the classification. Tools are supposed to be "
                f"off for this provider. It said: {text.strip()[:200]!r}"
            )
        return LLMResponse(text=text, tokens_used=_tokens(payload))


def _looks_like_json(text: str) -> bool:
    return ("{" in text and "}" in text) or ("[" in text and "]" in text)


def _parse_stream(stdout: str) -> tuple[dict | None, list[str], list[str]]:
    """Split a stream-json transcript into (result event, assistant texts, tool names).

    Thinking blocks are skipped deliberately: the model reasons about the schema
    before emitting it, and reasoning that *discusses* JSON would otherwise
    outrank the JSON.

    Malformed lines are skipped rather than fatal — the transcript is a stream,
    and one unparseable warning printed mid-run is not a reason to throw away a
    classification that completed.
    """
    result: dict | None = None
    turns: list[str] = []
    tools: list[str] = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "result":
            result = event
        elif event.get("type") == "assistant":
            for block in (event.get("message") or {}).get("content") or []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text":
                    turns.append(block.get("text") or "")
                elif block.get("type") == "tool_use":
                    tools.append(str(block.get("name") or "?"))
    return result, turns, tools


def _tokens(payload: dict) -> int | None:
    """Total tokens across every model the CLI used. None when unknown.

    Two traps. One invocation can span more than one model — a small one for
    internal bookkeeping alongside the one that answers — so the top-level
    `usage` block describes only part of the work. And the CLI caches its own
    prompt aggressively, so a call reporting inputTokens=2 may have read 12,000
    cached tokens and written 2,800 more; counting only input+output would
    under-report by an order of magnitude.
    """
    per_model = payload.get("modelUsage") or {}
    if per_model:
        return sum(
            int(m.get("inputTokens", 0))
            + int(m.get("outputTokens", 0))
            + int(m.get("cacheReadInputTokens", 0))
            + int(m.get("cacheCreationInputTokens", 0))
            for m in per_model.values()
            if isinstance(m, dict)
        )
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        return None  # unknown, NOT zero
    return (
        int(usage.get("input_tokens", 0))
        + int(usage.get("output_tokens", 0))
        + int(usage.get("cache_read_input_tokens", 0))
        + int(usage.get("cache_creation_input_tokens", 0))
    )


def _failure_blob(stdout: str, stderr: str) -> str:
    """The most informative ~300 chars of a failed run.

    Built, not concatenated. A stream-json transcript opens with a system/init
    banner listing the CLI's model, tools and every slash command it loaded —
    several hundred characters of the least useful text in the stream. With an
    empty stderr that banner IS the whole message and the real failure sits past
    the truncation, so the error reads as if the CLI died at startup.

    Result event first (where the CLI states its own error), then stderr, then
    the TAIL of stdout — on a crash, whatever happened last is the crash.
    """
    parts: list[str] = []
    result, _turns, _tools = _parse_stream(stdout)
    if result is not None:
        parts.append(json.dumps(result))
    if stderr.strip():
        parts.append(stderr.strip())
    body = stdout.strip()
    if body:
        lines = body.splitlines()
        parts.append("\n".join((lines[1:] if len(lines) > 1 else lines)[-8:]))
    return "\n".join(parts) if parts else "(no output on stdout or stderr)"


def _classify_failure(returncode: int, blob: str) -> LLMError:
    haystack = blob.lower()
    if any(m in haystack for m in _LIMIT_MARKERS):
        return LLMLimitError(
            f"Claude Code hit its subscription rate limit or quota. Nothing is "
            f"misconfigured — the account is out of allowance for now. "
            f"Output: {blob.strip()[:300]}"
        )
    if any(m in haystack for m in _AUTH_MARKERS):
        return LLMAuthError(
            f"Claude Code is installed but not authenticated. Output: {blob.strip()[:300]}"
        )
    return LLMError(f"Claude Code exited {returncode}: {blob.strip()[:300]}")
