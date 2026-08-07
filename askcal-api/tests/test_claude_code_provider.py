"""Claude Code provider — the real `claude` binary is never invoked.

Every test here pins a specific failure that this provider was written to avoid.
The docstrings say which one, because the code that prevents them looks
arbitrary otherwise.
"""

import asyncio
import json
import os

import pytest

from app.config import get_settings
from app.llm import claude_code as cc
from app.llm.base import (
    LLMAuthError,
    LLMError,
    LLMLimitError,
    LLMProvider,
    LLMUnavailableError,
)


@pytest.fixture(autouse=True)
def _fresh_settings():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


# ── fakes ─────────────────────────────────────────────────────────────────


class _FakeProc:
    def __init__(self, stdout: str = "", returncode: int = 0, stderr: str = "", hang: bool = False):
        self._out, self._err, self._hang = stdout, stderr, hang
        self.returncode = returncode
        self.killed = False
        self.reaped = False
        self.stdin_payload: bytes | None = None

    async def communicate(self, data: bytes | None = None):
        if self._hang:
            await asyncio.sleep(3600)  # tripped by the tiny configured timeout
        self.stdin_payload = data
        return self._out.encode(), self._err.encode()

    def kill(self) -> None:
        self.killed = True

    async def wait(self) -> int:
        self.reaped = True
        return self.returncode


def _result(**over) -> dict:
    payload = {
        "is_error": False,
        "subtype": "success",
        "stop_reason": "end_turn",
        "num_turns": 1,
        "result": '[{"gmail_id": "a"}]',
        "usage": {
            "input_tokens": 2,
            "output_tokens": 9,
            "cache_read_input_tokens": 11621,
            "cache_creation_input_tokens": 2807,
        },
        "modelUsage": {
            "claude-haiku-4-5": {
                "inputTokens": 530,
                "outputTokens": 13,
                "cacheReadInputTokens": 0,
                "cacheCreationInputTokens": 0,
            },
            "claude-sonnet-5": {
                "inputTokens": 2,
                "outputTokens": 9,
                "cacheReadInputTokens": 11621,
                "cacheCreationInputTokens": 2807,
            },
        },
    }
    payload.update(over)
    return payload


def _transcript(payload: dict, turns: list[str] | None = None, thinking: list[str] | None = None) -> str:
    """A `--output-format stream-json` transcript: turns, then the result event."""
    lines = []
    for t in thinking or []:
        lines.append(
            json.dumps(
                {"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": t}]}}
            )
        )
    for t in turns if turns is not None else [payload.get("result") or ""]:
        lines.append(
            json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": t}]}})
        )
    lines.append(json.dumps({"type": "result", **payload}))
    return "\n".join(lines) + "\n"


def _build(
    monkeypatch,
    *,
    payload: dict | None = None,
    stdout: str | None = None,
    turns: list[str] | None = None,
    thinking: list[str] | None = None,
    returncode: int = 0,
    stderr: str = "",
    hang: bool = False,
    env: dict[str, str] | None = None,
):
    """Provider with `claude` faked. Returns (provider, captured, proc)."""
    monkeypatch.setenv("ASKCAL_LLM_PROVIDER", "claude_code")
    for k, v in (env or {}).items():
        monkeypatch.setenv(k, v)
    get_settings.cache_clear()

    monkeypatch.setattr(cc.shutil, "which", lambda _b: "/usr/local/bin/claude")
    # Pin the host case. Without this the suite passes on macOS and fails when
    # CI itself runs inside Docker — where the container guard correctly fires.
    monkeypatch.setattr(cc, "running_in_container", lambda: False)

    out = stdout if stdout is not None else _transcript(payload or _result(), turns, thinking)
    proc = _FakeProc(out, returncode, stderr, hang)
    captured: dict = {}

    async def _exec(*argv, **kwargs):
        captured["argv"] = list(argv)
        captured["kwargs"] = kwargs
        return proc

    monkeypatch.setattr(cc.asyncio, "create_subprocess_exec", _exec)
    return cc.ClaudeCodeProvider(), captured, proc


def _run(provider, system="SYS", user="USER"):
    return asyncio.run(provider.complete(system, user))


# ── contract ──────────────────────────────────────────────────────────────


def test_satisfies_the_provider_protocol(monkeypatch):
    provider, _, _ = _build(monkeypatch)
    assert isinstance(provider, LLMProvider)


# ── invocation shape ──────────────────────────────────────────────────────


def test_prompt_goes_on_stdin_not_argv(monkeypatch):
    """As an argv element a real batch hits [Errno 7] Argument list too long."""
    big = "x" * 40_000
    provider, captured, proc = _build(monkeypatch)
    _run(provider, "SYS", big)

    assert proc.stdin_payload == big.encode()
    assert captured["kwargs"]["stdin"] is asyncio.subprocess.PIPE
    assert not any(big in str(a) for a in captured["argv"])


def test_asks_for_the_whole_transcript(monkeypatch):
    """--output-format json returns only the final turn; the answer is often earlier."""
    provider, captured, _ = _build(monkeypatch)
    _run(provider)
    argv = captured["argv"]
    assert argv[argv.index("--output-format") + 1] == "stream-json"
    assert "--verbose" in argv


def test_disables_tools_with_an_empty_allow_list(monkeypatch):
    """A deny-list missed ReportFindings, which ate the answer entirely."""
    provider, captured, _ = _build(monkeypatch)
    _run(provider)
    argv = captured["argv"]
    assert argv[argv.index("--tools") + 1] == ""
    assert "--disallowed-tools" not in argv


def test_replaces_rather_than_appends_the_system_prompt(monkeypatch):
    """Appending would stack our persona on the coding agent's and pay for both."""
    provider, captured, _ = _build(monkeypatch)
    _run(provider)
    argv = captured["argv"]
    assert argv[argv.index("--system-prompt") + 1] == "SYS"
    assert "--append-system-prompt" not in argv


def test_passes_the_configured_effort_and_model(monkeypatch):
    provider, captured, _ = _build(
        monkeypatch,
        env={"ASKCAL_CLAUDE_CODE_EFFORT": "medium", "ASKCAL_CLAUDE_CODE_MODEL": "haiku"},
    )
    _run(provider)
    argv = captured["argv"]
    assert argv[argv.index("--effort") + 1] == "medium"
    assert argv[argv.index("--model") + 1] == "haiku"


def test_runs_in_a_neutral_cwd(monkeypatch):
    """Inside the repo, Claude Code would read CLAUDE.md and ambient source files."""
    provider, captured, _ = _build(monkeypatch)
    _run(provider)
    cwd = captured["kwargs"]["cwd"]
    assert "askcal-classify-" in cwd
    assert cwd != os.getcwd()


# ── the billing test ──────────────────────────────────────────────────────


@pytest.mark.parametrize("token", ["sk-ant-oat01-test", ""])
def test_the_anthropic_api_key_never_reaches_the_cli(monkeypatch, token):
    """The CLI silently prefers an API key over the subscription credential.

    Both parameters matter. With a token, an inherited key would win over it.
    Without one, the CLI is supposed to fall back to ~/.claude on the host — and
    the inherited key silently overrides that too. Either way the work gets
    billed to Console credits while looking like it rode the subscription.
    """
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-api03-console-credits")
    monkeypatch.setenv("ANTHROPIC_AUTH_TOKEN", "nope")
    monkeypatch.setenv("ANTHROPIC_BASE_URL", "https://proxy.example/v1")
    provider, captured, _ = _build(
        monkeypatch, env={"ASKCAL_CLAUDE_CODE_OAUTH_TOKEN": token}
    )
    _run(provider)

    env = captured["kwargs"]["env"]
    assert "ANTHROPIC_API_KEY" not in env
    assert "ANTHROPIC_AUTH_TOKEN" not in env
    assert "ANTHROPIC_BASE_URL" not in env
    assert env.get("CLAUDE_CODE_OAUTH_TOKEN", "") == token
    # Inherited, not replaced — without PATH the CLI cannot find node.
    assert "PATH" in env


# ── transcript reading ────────────────────────────────────────────────────


def test_reads_the_answer_from_an_earlier_turn(monkeypatch):
    """The agent loop answers in turn 1 and writes a summary in turn 2."""
    provider, _, _ = _build(
        monkeypatch,
        turns=['[{"gmail_id": "a"}]', "Classification complete — 1 email processed."],
    )
    assert _run(provider).text == '[{"gmail_id": "a"}]'


def test_ignores_thinking_that_discusses_json(monkeypatch):
    """Reasoning *about* the schema would otherwise outrank the schema."""
    provider, _, _ = _build(
        monkeypatch,
        thinking=['I should return a JSON array like [{"gmail_id": ...}] here.'],
        turns=['[{"gmail_id": "real"}]'],
    )
    assert _run(provider).text == '[{"gmail_id": "real"}]'


def test_survives_a_junk_line_in_the_transcript(monkeypatch):
    """One warning printed mid-stream must not discard a completed run."""
    good = _transcript(_result(), turns=['[{"gmail_id": "a"}]'])
    lines = good.splitlines()
    lines.insert(1, "warning: something unparseable")
    provider, _, _ = _build(monkeypatch, stdout="\n".join(lines) + "\n")
    assert _run(provider).text == '[{"gmail_id": "a"}]'


def test_names_the_tool_it_answered_with(monkeypatch):
    """"No JSON found" was true and useless — it blamed the parser."""
    stdout = "\n".join(
        [
            json.dumps(
                {
                    "type": "assistant",
                    "message": {
                        "content": [
                            {"type": "tool_use", "name": "ReportFindings"},
                            {"type": "text", "text": "2 findings reported."},
                        ]
                    },
                }
            ),
            json.dumps({"type": "result", **_result(result="2 findings reported.")}),
        ]
    )
    provider, _, _ = _build(monkeypatch, stdout=stdout)
    with pytest.raises(LLMError, match="ReportFindings"):
        _run(provider)


# ── token accounting ──────────────────────────────────────────────────────


def test_counts_cached_tokens_across_every_model(monkeypatch):
    """inputTokens=2 can accompany 11k cached reads; input+output under-reports."""
    provider, _, _ = _build(monkeypatch)
    # haiku 530+13 + sonnet 2+9+11621+2807
    assert _run(provider).tokens_used == 14_982


def test_falls_back_to_top_level_usage(monkeypatch):
    payload = _result()
    del payload["modelUsage"]
    provider, _, _ = _build(monkeypatch, payload=payload)
    assert _run(provider).tokens_used == 2 + 9 + 11621 + 2807


def test_unknown_usage_is_none_not_zero(monkeypatch):
    """A 0 would read as "this classification was free"."""
    payload = _result()
    del payload["modelUsage"]
    del payload["usage"]
    provider, _, _ = _build(monkeypatch, payload=payload)
    assert _run(provider).tokens_used is None


# ── failure classification ────────────────────────────────────────────────


def test_rate_limit_is_distinguishable_from_a_parse_failure(monkeypatch):
    """Nothing is misconfigured — the account is out of allowance."""
    provider, _, _ = _build(
        monkeypatch,
        stdout="",
        stderr="5-hour limit reached, resets at 3pm",
        returncode=1,
    )
    with pytest.raises(LLMLimitError):
        _run(provider)


def test_a_limit_in_a_clean_exit_payload_still_raises(monkeypatch):
    """A limit can arrive as exit 0 with an error payload."""
    payload = _result(is_error=True, subtype="error_during_execution", result="usage limit reached")
    provider, _, _ = _build(monkeypatch, payload=payload)
    with pytest.raises(LLMLimitError):
        _run(provider)


def test_unauthenticated_cli_is_named_as_such(monkeypatch):
    provider, _, _ = _build(
        monkeypatch, stdout="", stderr="Not logged in. Please run /login", returncode=1
    )
    with pytest.raises(LLMAuthError):
        _run(provider)


def test_an_ordinary_crash_is_a_plain_error(monkeypatch):
    provider, _, _ = _build(monkeypatch, stdout="", stderr="segfault", returncode=139)
    with pytest.raises(LLMError) as exc:
        _run(provider)
    assert not isinstance(exc.value, (LLMLimitError, LLMAuthError))


def test_non_transcript_stdout_raises_cleanly(monkeypatch):
    """Never let a raw JSONDecodeError escape — it reads as a parser bug."""
    provider, _, _ = _build(monkeypatch, stdout="command not found\n")
    with pytest.raises(LLMError, match="did not return a transcript"):
        _run(provider)


def test_timeout_kills_and_reaps_the_child(monkeypatch):
    """wait_for cancels communicate() but does not reap — the child would leak.

    A surviving `claude` keeps burning quota for the container's lifetime and
    outlives the temp directory it is running in.
    """
    provider, _, proc = _build(
        monkeypatch, hang=True, env={"ASKCAL_CLAUDE_CODE_TIMEOUT_SECONDS": "0.01"}
    )
    with pytest.raises(LLMError, match="timed out"):
        _run(provider)
    assert proc.killed
    assert proc.reaped


# ── construction guards ───────────────────────────────────────────────────


def test_missing_binary_fails_at_construction(monkeypatch):
    """A misconfiguration should surface at startup, not mid-sync."""
    monkeypatch.setenv("ASKCAL_LLM_PROVIDER", "claude_code")
    get_settings.cache_clear()
    monkeypatch.setattr(cc.shutil, "which", lambda _b: None)
    monkeypatch.setattr(cc, "running_in_container", lambda: False)
    with pytest.raises(LLMUnavailableError, match="not on PATH"):
        cc.ClaudeCodeProvider()


def test_container_without_a_token_is_rejected(monkeypatch):
    """There is no home directory holding credentials inside a container."""
    monkeypatch.setenv("ASKCAL_LLM_PROVIDER", "claude_code")
    monkeypatch.setenv("ASKCAL_CLAUDE_CODE_OAUTH_TOKEN", "")
    get_settings.cache_clear()
    monkeypatch.setattr(cc.shutil, "which", lambda _b: "/usr/local/bin/claude")
    monkeypatch.setattr(cc, "running_in_container", lambda: True)
    with pytest.raises(LLMAuthError) as exc:
        cc.ClaudeCodeProvider()
    assert "claude setup-token" in str(exc.value)
    assert "ASKCAL_CLAUDE_CODE_OAUTH_TOKEN" in str(exc.value)


def test_container_with_a_token_constructs(monkeypatch):
    monkeypatch.setenv("ASKCAL_LLM_PROVIDER", "claude_code")
    monkeypatch.setenv("ASKCAL_CLAUDE_CODE_OAUTH_TOKEN", "sk-ant-oat01-test")
    get_settings.cache_clear()
    monkeypatch.setattr(cc.shutil, "which", lambda _b: "/usr/local/bin/claude")
    monkeypatch.setattr(cc, "running_in_container", lambda: True)
    assert cc.ClaudeCodeProvider().model_name


# ── registry ──────────────────────────────────────────────────────────────


def test_registry_selects_claude_code_on_config(monkeypatch):
    from app.llm.registry import build_provider

    monkeypatch.setenv("ASKCAL_LLM_PROVIDER", "claude_code")
    get_settings.cache_clear()
    monkeypatch.setattr(cc.shutil, "which", lambda _b: "/usr/local/bin/claude")
    monkeypatch.setattr(cc, "running_in_container", lambda: False)
    assert isinstance(build_provider(), cc.ClaudeCodeProvider)
