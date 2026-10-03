import email.message
import io
import json
import urllib.error
import urllib.request
from typing import Any

import agent_spend
import pytest

# Fabricated response bodies for the two pages of a usage-events request,
# with the fields the report reads; costs are in US cents. Run bc-run-a has
# an event on each page. Run bc-run-b's event was billed per request, so it
# has no tokenUsage. The editor and Bugbot events came from no cloud agent run.
USAGE_EVENT_PAGES = [
    """{"pagination": {"hasNextPage": true}, "usageEvents": [
  {"timestamp": "1790935200000", "model": "claude-opus-5-5-xhigh", "cloudAgentId": "bc-run-a", "chargedCents": 3550.0,
   "tokenUsage": {"inputTokens": 100, "outputTokens": 2000, "cacheWriteTokens": 3000, "cacheReadTokens": 40000}},
  {"timestamp": "1790845200000", "model": "composer-2.5", "chargedCents": 125.0,
   "tokenUsage": {"inputTokens": 10, "outputTokens": 20, "cacheWriteTokens": 30, "cacheReadTokens": 40}}
]}""",
    """{"pagination": {"hasNextPage": false}, "usageEvents": [
  {"timestamp": "1790933400000", "model": "claude-sonnet-5-5-high", "cloudAgentId": "bc-run-a", "chargedCents": 50.0,
   "tokenUsage": {"inputTokens": 1, "outputTokens": 2, "cacheWriteTokens": 3, "cacheReadTokens": 4}},
  {"timestamp": "1790769600000", "model": "claude-sonnet-5-5-high", "cloudAgentId": "bc-run-b", "chargedCents": 400.0},
  {"timestamp": "1790869500000", "model": "github_bugbot", "chargedCents": 0,
   "tokenUsage": {"inputTokens": 500, "outputTokens": 600, "cacheWriteTokens": 0, "cacheReadTokens": 700}}
]}""",
]

EXPECTED_REPORT = """\
Cursor usage from 2026-09-26 00:00 UTC up to 2026-10-03 00:00 UTC.

| Cloud agent run | First event (UTC) | Models | Events | Input tokens | Output tokens | Cache write tokens | Cache read tokens | Cost ($) |
|---|---|---|--:|--:|--:|--:|--:|--:|
| bc-run-a | 2026-10-02 09:30 | claude-opus-5-5-xhigh, claude-sonnet-5-5-high | 2 | 101 | 2,002 | 3,003 | 40,004 | 36.00 |
| bc-run-b | 2026-09-30 12:00 | claude-sonnet-5-5-high | 1 | 0 | 0 | 0 | 0 | 4.00 |

| Total | Events | Input tokens | Output tokens | Cache write tokens | Cache read tokens | Cost ($) |
|---|--:|--:|--:|--:|--:|--:|
| All 2 cloud agent runs | 3 | 101 | 2,002 | 3,003 | 40,004 | 40.00 |
| Usage outside cloud agent runs | 2 | 510 | 620 | 30 | 740 | 1.25 |
| All usage | 5 | 611 | 2,622 | 3,033 | 40,744 | 41.25 |
"""


def test_report_totals_tokens_and_cost_per_cloud_agent_run(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    requests: list[tuple[str | None, dict[str, Any]]] = []

    def fake_urlopen(request: urllib.request.Request, timeout: float) -> io.BytesIO:
        assert isinstance(request.data, bytes)
        request_body = json.loads(request.data)
        requests.append((request.get_header("Authorization"), request_body))
        page: int = request_body["page"]
        return io.BytesIO(USAGE_EVENT_PAGES[page - 1].encode())

    monkeypatch.setenv("CURSOR_ADMIN_API_KEY", "test-key")
    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    exit_code = agent_spend.main(["--since", "2026-09-26", "--until", "2026-10-03"])

    assert exit_code == 0
    assert capsys.readouterr().out == EXPECTED_REPORT
    # Basic authentication with the key as the user name and no password;
    # endDate is a millisecond before --until, because the API includes it.
    window = {"startDate": 1790380800000, "endDate": 1790985599999, "pageSize": 1000}
    assert requests == [
        ("Basic dGVzdC1rZXk6", {**window, "page": 1}),
        ("Basic dGVzdC1rZXk6", {**window, "page": 2}),
    ]


def test_report_fails_without_calling_the_api_when_the_key_is_not_set(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    def fail_urlopen(request: urllib.request.Request, timeout: float) -> io.BytesIO:
        raise AssertionError("the report called the Admin API without a key")

    monkeypatch.delenv("CURSOR_ADMIN_API_KEY", raising=False)
    monkeypatch.setattr(urllib.request, "urlopen", fail_urlopen)

    assert agent_spend.main([]) == 1
    assert "error: CURSOR_ADMIN_API_KEY is not set." in capsys.readouterr().err


def test_report_fails_with_the_api_error_text_when_the_api_rejects_the_key(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    rejection = b'{"code":"error","message":"Invalid Team API Key"}'

    def reject_urlopen(request: urllib.request.Request, timeout: float) -> io.BytesIO:
        headers = email.message.Message()
        raise urllib.error.HTTPError(
            request.full_url, 401, "Unauthorized", headers, io.BytesIO(rejection)
        )

    monkeypatch.setenv("CURSOR_ADMIN_API_KEY", "test-key")
    monkeypatch.setattr(urllib.request, "urlopen", reject_urlopen)

    assert agent_spend.main([]) == 1
    assert capsys.readouterr().err == (
        "error: https://api.cursor.com/teams/filtered-usage-events returned HTTP 401: "
        '{"code":"error","message":"Invalid Team API Key"}\n'
    )
