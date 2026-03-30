#!/usr/bin/env python3
"""
data/positions_db.py
─────────────────────────────────────────────────────────────────────────────
SQLite journal for all positions — bot and manual.
Never wiped. Single source of historical truth.

Schema:
    positions   — every position opened (fill received)
    settlements — every position closed (settlement received)
"""

import sqlite3
import logging
import os
from datetime import datetime, timezone

log = logging.getLogger("kalshi_bot.positions_db")
DB_PATH = "/root/kalshi-bot-v2/data/positions.db"


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS positions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        ticker          TEXT NOT NULL,
        order_id        TEXT,
        client_order_id TEXT,
        side            TEXT,
        qty             INTEGER,
        entry_price     REAL,
        cost_basis      REAL,
        source          TEXT DEFAULT 'unknown',
        strategy        TEXT,
        entry_time      TEXT,
        status          TEXT DEFAULT 'open',
        created_at      TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS settlements (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        ticker          TEXT NOT NULL,
        revenue         REAL,
        pnl             REAL,
        source          TEXT DEFAULT 'unknown',
        strategy        TEXT,
        entry_price     REAL,
        exit_price      REAL,
        settled_at      TEXT,
        created_at      TEXT DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_positions_ticker  ON positions(ticker);
    CREATE INDEX IF NOT EXISTS idx_positions_source  ON positions(source);
    CREATE INDEX IF NOT EXISTS idx_settlements_source ON settlements(source);
    """)
    conn.commit()
    conn.close()
    log.info(f"[PositionsDB] Initialized at {DB_PATH}")


def record_fill(ticker: str, order_id: str, client_order_id: str,
                side: str, qty: int, entry_price: float,
                source: str = 'unknown', strategy: str = ''):
    """Record a fill when a position is opened."""
    cost_basis = qty * entry_price / 100.0
    conn = get_db()
    try:
        conn.execute("""
            INSERT OR IGNORE INTO positions
            (ticker, order_id, client_order_id, side, qty,
             entry_price, cost_basis, source, strategy, entry_time, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open')
        """, (ticker, order_id, client_order_id, side, qty,
              entry_price, cost_basis, source, strategy,
              datetime.now(timezone.utc).isoformat()[:16]))
        conn.commit()
        log.info(f"[PositionsDB] Recorded fill: {ticker} {side} @ {entry_price}¢ source={source}")
    except Exception as e:
        log.warning(f"[PositionsDB] Fill record failed: {e}")
    finally:
        conn.close()


def record_settlement(ticker: str, revenue: float,
                      source: str = 'unknown', strategy: str = ''):
    """Record a settlement when a position closes."""
    conn = get_db()
    try:
        # Find matching open position
        pos = conn.execute(
            "SELECT * FROM positions WHERE ticker=? AND status='open' LIMIT 1",
            (ticker,)
        ).fetchone()

        entry_price = pos['entry_price'] if pos else 0
        cost_basis  = pos['cost_basis']  if pos else 0
        pnl         = revenue - cost_basis
        src         = pos['source']      if pos else source
        strat       = pos['strategy']    if pos else strategy

        conn.execute("""
            INSERT INTO settlements
            (ticker, revenue, pnl, source, strategy, entry_price,
             exit_price, settled_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (ticker, revenue, pnl, src, strat, entry_price,
              revenue, datetime.now(timezone.utc).isoformat()[:16]))

        # Mark position as closed
        if pos:
            conn.execute(
                "UPDATE positions SET status='closed' WHERE id=?",
                (pos['id'],)
            )

        conn.commit()
        log.info(f"[PositionsDB] Settlement: {ticker} revenue=${revenue:.2f} pnl=${pnl:.2f}")
    except Exception as e:
        log.warning(f"[PositionsDB] Settlement record failed: {e}")
    finally:
        conn.close()


def get_pnl_summary() -> dict:
    """Get PNL summary split by source."""
    conn = get_db()
    try:
        rows = conn.execute("""
            SELECT source,
                   COUNT(*)        as n,
                   SUM(CASE WHEN pnl > 0 THEN 1 ELSE 0 END) as wins,
                   SUM(revenue)    as revenue,
                   SUM(pnl)        as pnl
            FROM settlements
            GROUP BY source
        """).fetchall()

        result = {}
        for r in rows:
            result[r['source']] = {
                'n':       r['n'],
                'wins':    r['wins'],
                'revenue': round(r['revenue'] or 0, 2),
                'pnl':     round(r['pnl'] or 0, 2),
                'win_rate': round(r['wins'] / r['n'] * 100, 1) if r['n'] else 0,
            }
        return result
    finally:
        conn.close()


def get_open_positions(source: str = None) -> list:
    """Get all open positions, optionally filtered by source."""
    conn = get_db()
    try:
        if source:
            rows = conn.execute(
                "SELECT * FROM positions WHERE status='open' AND source=? ORDER BY entry_time DESC",
                (source,)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM positions WHERE status='open' ORDER BY entry_time DESC"
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_recent_settlements(limit: int = 20, source: str = None) -> list:
    """Get recent settlements."""
    conn = get_db()
    try:
        if source:
            rows = conn.execute(
                "SELECT * FROM settlements WHERE source=? ORDER BY settled_at DESC LIMIT ?",
                (source, limit)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM settlements ORDER BY settled_at DESC LIMIT ?",
                (limit,)
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_strategy_performance() -> list:
    """Get performance broken down by strategy."""
    conn = get_db()
    try:
        rows = conn.execute("""
            SELECT strategy,
                   COUNT(*)   as n,
                   SUM(CASE WHEN pnl > 0 THEN 1 ELSE 0 END) as wins,
                   SUM(pnl)   as total_pnl,
                   AVG(pnl)   as avg_pnl
            FROM settlements
            WHERE strategy != ''
            GROUP BY strategy
            ORDER BY total_pnl DESC
        """).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


# Initialize on import
init_db()
