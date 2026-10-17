-- ============================================================
--  TRADING JOURNAL — SCHEMA
--  SQL Analytics Project · Mohit Grewal (madme.org)
--  Dialect: standard SQL (PostgreSQL-compatible)
--  The journal behind the fleet: every bot decision leaves a
--  row, every risk-rail event leaves a row. Nothing is vibes.
-- ============================================================

-- One row per executed trade.
CREATE TABLE trades (
    trade_id      BIGINT PRIMARY KEY,
    bot           TEXT        NOT NULL,            -- Scout / Rookie / Ace-shadow etc.
    strategy      TEXT        NOT NULL,            -- e.g. 'Confluence A'
    instrument    TEXT        NOT NULL,            -- e.g. 'XAU_USD'
    direction     TEXT        NOT NULL CHECK (direction IN ('LONG','SHORT')),
    session       TEXT        NOT NULL,            -- Asia / London / NY open / Overlap
    opened_at     TIMESTAMP   NOT NULL,
    closed_at     TIMESTAMP,
    units         NUMERIC     NOT NULL,
    entry_price   NUMERIC     NOT NULL,
    exit_price    NUMERIC,
    pnl           NUMERIC,                          -- realised P&L in account currency
    r_multiple    NUMERIC,                          -- P&L in units of initial risk (R)
    is_manual     BOOLEAN     NOT NULL DEFAULT FALSE  -- operator's own trades are flagged, never mixed into bot stats
);

-- One row per signal the engine evaluated (taken or vetoed).
CREATE TABLE signals (
    signal_id     BIGINT PRIMARY KEY,
    bot           TEXT        NOT NULL,
    strategy      TEXT        NOT NULL,
    instrument    TEXT        NOT NULL,
    generated_at  TIMESTAMP   NOT NULL,
    strength      NUMERIC     NOT NULL,            -- 0.00–1.00 confluence score
    adx           NUMERIC,                          -- trend strength at signal time
    decision      TEXT        NOT NULL CHECK (decision IN ('TAKEN','VETOED','SKIPPED')),
    veto_reason   TEXT                               -- e.g. 'NEWS', 'ADX_GATE', 'RISK_RAIL'
);

-- One row per risk-rail event. The rails are the product.
CREATE TABLE risk_events (
    event_id      BIGINT PRIMARY KEY,
    bot           TEXT        NOT NULL,
    event_type    TEXT        NOT NULL CHECK (event_type IN ('DAILY_HALT','DD_KILL','BREAKEVEN_MOVE','NEWS_VETO')),
    occurred_at   TIMESTAMP   NOT NULL,
    equity        NUMERIC     NOT NULL,
    detail        TEXT
);

CREATE INDEX idx_trades_bot_time   ON trades (bot, opened_at);
CREATE INDEX idx_trades_strategy   ON trades (strategy);
CREATE INDEX idx_signals_decision  ON signals (decision);
CREATE INDEX idx_risk_time         ON risk_events (occurred_at);
