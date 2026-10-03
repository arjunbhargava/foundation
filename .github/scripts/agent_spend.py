"""Report tokens and cost per Cursor cloud agent run, from the Cursor Admin API.

Run it with ``mise run spend``; arguments after ``--`` go to this script, for
example ``mise run spend -- --since 2026-09-26``. It reads a team Admin API
key from the environment variable ``CURSOR_ADMIN_API_KEY``, fetches every
usage event in the window from the Admin API's usage-events endpoint, and
prints two Markdown tables: one row per cloud agent run, most expensive first,
then totals for all runs, for usage outside them (people's editors and Bugbot,
for example), and for all usage. The last total is the one to compare with
the dashboard's usage total for the same window.

Cost is each event's ``chargedCents``: the model cost plus the Cursor Token
Rate, whether paid on demand or from the plan's included usage. The Admin API
documents it as the field that matches the dashboard's totals.
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Self

ADMIN_KEY_VARIABLE = "CURSOR_ADMIN_API_KEY"
USAGE_EVENTS_URL = "https://api.cursor.com/teams/filtered-usage-events"
EVENTS_PER_PAGE = 1000  # The endpoint's maximum.
REQUEST_TIMEOUT_S = 60
DEFAULT_WINDOW = timedelta(days=7)
UNIX_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
COUNT_COLUMNS = "Events | Input tokens | Output tokens | Cache write tokens | Cache read tokens | Cost ($)"
COUNT_ALIGNMENT = "--:|--:|--:|--:|--:|--:"

type UsageEvent = dict[str, Any]


def main(argv: Sequence[str] | None = None) -> int:
    """Print the spend report for the window the command-line arguments give.

    Args:
        argv: command-line arguments without the program name; ``None`` reads
            ``sys.argv``.

    Returns:
        0 after printing the report to stdout; 1 if ``CURSOR_ADMIN_API_KEY``
        is not set or the Admin API returns an HTTP error, with the reason on
        stderr.
    """
    since, until = _parse_window(argv)
    api_key = os.environ.get(ADMIN_KEY_VARIABLE)
    if not api_key:
        print(
            f"error: {ADMIN_KEY_VARIABLE} is not set. Set it to a Cursor team Admin API key: "
            "for cloud agents, as a secret under Cloud Agents > Secrets in the Cursor dashboard.",
            file=sys.stderr,
        )
        return 1

    try:
        events = fetch_usage_events(api_key, since, until)
    except urllib.error.HTTPError as error:
        with error:
            response_text = error.read().decode(errors="replace")
        print(
            f"error: {USAGE_EVENTS_URL} returned HTTP {error.code}: {response_text}",
            file=sys.stderr,
        )
        return 1

    events_by_run, events_outside_runs = split_by_run(events)
    print(format_report(since, until, events_by_run, events_outside_runs))
    return 0


def _parse_window(argv: Sequence[str] | None) -> tuple[datetime, datetime]:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--since",
        type=_parse_utc_time,
        help="start of the window, an ISO 8601 date or time, UTC unless it gives an offset; "
        "default: 7 days before --until",
    )
    parser.add_argument(
        "--until",
        type=_parse_utc_time,
        help="end of the window, excluded; default: now",
    )
    arguments = parser.parse_args(argv)

    until: datetime = arguments.until or datetime.now(UTC)
    since: datetime = arguments.since or until - DEFAULT_WINDOW
    if since >= until:
        parser.error(
            f"--since ({since:%Y-%m-%d %H:%M} UTC) must be before --until ({until:%Y-%m-%d %H:%M} UTC)"
        )
    return since, until


def _parse_utc_time(text: str) -> datetime:
    try:
        time = datetime.fromisoformat(text)
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"{text!r} is not an ISO 8601 date or time, such as 2026-09-26 or 2026-09-26T13:00Z"
        ) from None
    return time.replace(tzinfo=UTC) if time.tzinfo is None else time.astimezone(UTC)


def fetch_usage_events(
    api_key: str, since: datetime, until: datetime
) -> list[UsageEvent]:
    """Fetch every team usage event from ``since`` up to, but excluding, ``until``.

    Args:
        api_key: a Cursor team Admin API key.
        since: start of the window, included; timezone-aware.
        until: end of the window, excluded; timezone-aware.

    Returns:
        The events as the Admin API returns them, newest first.

    Raises:
        urllib.error.HTTPError: the Admin API rejected a request, for example
            with 401 for an invalid key or 429 above 60 requests a minute.
        urllib.error.URLError: the Admin API could not be reached.
    """
    credentials = base64.b64encode(f"{api_key}:".encode()).decode()
    window = {
        "startDate": _epoch_ms(since),
        # endDate is inclusive, so a window that ends where the next starts
        # stops a millisecond short to count no event twice.
        "endDate": _epoch_ms(until) - 1,
    }
    events: list[UsageEvent] = []
    page = 1
    while True:
        request = urllib.request.Request(
            USAGE_EVENTS_URL,
            data=json.dumps(
                {**window, "page": page, "pageSize": EVENTS_PER_PAGE}
            ).encode(),
            headers={
                "Authorization": f"Basic {credentials}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_S) as response:
            response_body = json.load(response)
        events += response_body["usageEvents"]
        if not response_body["pagination"]["hasNextPage"]:
            return events
        page += 1


def _epoch_ms(time: datetime) -> int:
    return (time - UNIX_EPOCH) // timedelta(milliseconds=1)


def split_by_run(
    events: list[UsageEvent],
) -> tuple[dict[str, list[UsageEvent]], list[UsageEvent]]:
    """Group usage events by the cloud agent run they came from.

    Args:
        events: usage events as the Admin API returns them.

    Returns:
        A map from each cloud agent run's ID (``bc-...``) to its events, and
        the events that came from no cloud agent run.
    """
    events_by_run: dict[str, list[UsageEvent]] = {}
    events_outside_runs: list[UsageEvent] = []
    for event in events:
        run_id = event.get("cloudAgentId")
        if run_id:
            events_by_run.setdefault(run_id, []).append(event)
        else:
            events_outside_runs.append(event)
    return events_by_run, events_outside_runs


def format_report(
    since: datetime,
    until: datetime,
    events_by_run: dict[str, list[UsageEvent]],
    events_outside_runs: list[UsageEvent],
) -> str:
    """Format usage as a Markdown table of cloud agent runs and a table of totals.

    Args:
        since: start of the window, in UTC.
        until: end of the window, excluded, in UTC.
        events_by_run: each cloud agent run's events, by run ID.
        events_outside_runs: the events that came from no cloud agent run.

    Returns:
        The report: a title line, one row per run in descending order of cost,
        then totals for all runs, for usage outside them, and for all usage.
    """
    usage_by_run = {
        run_id: Usage.total(events) for run_id, events in events_by_run.items()
    }
    runs_by_cost = sorted(
        usage_by_run.items(), key=lambda run: run[1].charged_cents, reverse=True
    )
    run_events = [event for events in events_by_run.values() for event in events]
    totals = {
        f"All {len(usage_by_run)} cloud agent runs": Usage.total(run_events),
        "Usage outside cloud agent runs": Usage.total(events_outside_runs),
        "All usage": Usage.total(run_events + events_outside_runs),
    }

    run_rows = [
        f"| {run_id} | {usage.first_event_time:%Y-%m-%d %H:%M} | {', '.join(usage.models)} | {_format_counts(usage)} |"
        for run_id, usage in runs_by_cost
    ]
    total_rows = [
        f"| {label} | {_format_counts(usage)} |" for label, usage in totals.items()
    ]
    return "\n".join(
        [
            f"Cursor usage from {since:%Y-%m-%d %H:%M} UTC up to {until:%Y-%m-%d %H:%M} UTC.",
            "",
            f"| Cloud agent run | First event (UTC) | Models | {COUNT_COLUMNS} |",
            f"|---|---|---|{COUNT_ALIGNMENT}|",
            *run_rows,
            "",
            f"| Total | {COUNT_COLUMNS} |",
            f"|---|{COUNT_ALIGNMENT}|",
            *total_rows,
        ]
    )


def _format_counts(usage: Usage) -> str:
    counts = [
        usage.event_count,
        usage.input_tokens,
        usage.output_tokens,
        usage.cache_write_tokens,
        usage.cache_read_tokens,
    ]
    return " | ".join(
        [*(f"{count:,}" for count in counts), f"{usage.charged_cents / 100:,.2f}"]
    )


@dataclass(frozen=True)
class Usage:
    """Token and cost totals of a set of usage events.

    Attributes:
        event_count: number of usage events. The Admin API aggregates a
            conversation's requests into events, so this is not a request
            count.
        input_tokens: prompt tokens not read from or written to the cache.
        output_tokens: tokens the model generated.
        cache_write_tokens: prompt tokens written to the cache.
        cache_read_tokens: prompt tokens read from the cache.
        charged_cents: sum of the events' ``chargedCents``, in US cents.
        models: the models the events used, sorted by name.
        first_event_time: time of the earliest event, in UTC; ``None`` if
            there are no events.
    """

    event_count: int
    input_tokens: int
    output_tokens: int
    cache_write_tokens: int
    cache_read_tokens: int
    charged_cents: float
    models: list[str]
    first_event_time: datetime | None

    @classmethod
    def total(cls, events: list[UsageEvent]) -> Self:
        """Total usage events as the Admin API returns them.

        Args:
            events: usage events; each has ``timestamp`` (epoch milliseconds,
                as a string), ``model``, and ``chargedCents``, and has
                ``tokenUsage`` only if it was billed by tokens.

        Returns:
            The events' totals.
        """
        token_counts = [
            event["tokenUsage"] for event in events if "tokenUsage" in event
        ]
        return cls(
            event_count=len(events),
            input_tokens=sum(tokens["inputTokens"] for tokens in token_counts),
            output_tokens=sum(tokens["outputTokens"] for tokens in token_counts),
            cache_write_tokens=sum(
                tokens["cacheWriteTokens"] for tokens in token_counts
            ),
            cache_read_tokens=sum(tokens["cacheReadTokens"] for tokens in token_counts),
            charged_cents=sum(event["chargedCents"] for event in events),
            models=sorted({event["model"] for event in events}),
            first_event_time=min(
                (
                    UNIX_EPOCH + timedelta(milliseconds=int(event["timestamp"]))
                    for event in events
                ),
                default=None,
            ),
        )


if __name__ == "__main__":
    sys.exit(main())
