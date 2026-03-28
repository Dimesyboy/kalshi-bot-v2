#!/usr/bin/env python3
"""
combo_scheduler.py
─────────────────────────────────────────────────────────────────────────────
Schedules combo_scanner.py runs based on tonight's NBA tip-off times.
Runs 2 hours and 30 minutes before each unique tip-off time.
Deduplicates overlapping scan times.
"""

import logging
import time
import subprocess
import sys
import requests
from datetime import datetime, timezone, timedelta, date

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("combo_scheduler")

SCAN_OFFSETS_MINS = [-120, -30]
SCAN_WINDOW_SECS  = 300   # Treat scan times within 5 min as the same


def get_todays_tip_times() -> list[datetime]:
    today = date.today().strftime("%Y%m%d")
    url   = f"https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates={today}"
    try:
        data = requests.get(url, timeout=8).json()
        tips = []
        for event in data.get("events", []):
            dt_str = event.get("date", "")
            if dt_str:
                dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
                name = event.get("name", "")
                log.info(f"  Game: {name} @ {dt.astimezone().strftime('%I:%M %p %Z')}")
                tips.append(dt)
        return sorted(set(tips))
    except Exception as e:
        log.error(f"Schedule fetch failed: {e}")
        return []


def build_schedule(tip_times: list[datetime]) -> list[datetime]:
    now   = datetime.now(timezone.utc)
    scans = []

    for tip in tip_times:
        for offset in SCAN_OFFSETS_MINS:
            scan_time = tip + timedelta(minutes=offset)
            if scan_time <= now:
                continue
            # Deduplicate — skip if within 5 min of existing scan
            if any(abs((scan_time - s).total_seconds()) < SCAN_WINDOW_SECS for s in scans):
                continue
            scans.append(scan_time)

    return sorted(scans)


def run_scan():
    log.info("=" * 50)
    log.info("RUNNING COMBO SCAN — LIVE")
    log.info("=" * 50)
    subprocess.run(
        [sys.executable, "/root/kalshi-bot-v2/combo_scanner.py", "--live"],
        cwd="/root/kalshi-bot-v2"
    )


def main():
    log.info("Combo Scheduler starting")
    log.info("Fetching today's NBA schedule...")

    tip_times = get_todays_tip_times()
    if not tip_times:
        log.warning("No games today — exiting")
        return

    schedule = build_schedule(tip_times)
    if not schedule:
        log.warning("No future scan times — all games already started")
        # Run once now anyway
        run_scan()
        return

    log.info(f"\nScheduled {len(schedule)} scans:")
    for s in schedule:
        log.info(f"  {s.astimezone().strftime('%I:%M %p %Z')}")

    for scan_time in schedule:
        now  = datetime.now(timezone.utc)
        wait = (scan_time - now).total_seconds()
        if wait > 0:
            log.info(f"\nSleeping {int(wait/60)}min until {scan_time.astimezone().strftime('%I:%M %p %Z')}")
            time.sleep(wait)
        run_scan()

    log.info("All scans complete for today")


if __name__ == "__main__":
    main()
