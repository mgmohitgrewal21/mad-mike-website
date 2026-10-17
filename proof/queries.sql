-- ============================================================
--  TRADING JOURNAL — ANALYTICS QUERIES
--  SQL Analytics Project · Mohit Grewal (madme.org)
--  Schema: schema.sql · Dialect: standard SQL (PostgreSQL)
--  Ten questions a trading operator actually asks, answered
--  with joins, CTEs, aggregates and window functions.
-- ============================================================

-- Q1 · Strategy scorecard — trades, win rate, net P&L, avg R per strategy.
-- (Bot trades only: manual trades are flagged and excluded.)
SELECT
    strategy,
    COUNT(*)                                            AS trades,
    ROUND(100.0 * AVG(CASE WHEN pnl > 0 THEN 1 ELSE 0 END), 1) AS win_rate_pct,
    ROUND(SUM(pnl), 2)                                  AS net_pnl,
    ROUND(AVG(r_multiple), 2)                           AS avg_r
FROM trades
WHERE closed_at IS NOT NULL
  AND is_manual = FALSE
GROUP BY strategy
ORDER BY net_pnl DESC;

-- Q2 · Win rate by session — where does the edge actually live?
SELECT
    session,
    COUNT(*)                                            AS trades,
    ROUND(100.0 * AVG(CASE WHEN pnl > 0 THEN 1 ELSE 0 END), 1) AS win_rate_pct,
    ROUND(SUM(pnl), 2)                                  AS net_pnl
FROM trades
WHERE closed_at IS NOT NULL AND is_manual = FALSE
GROUP BY session
ORDER BY win_rate_pct DESC;

-- Q3 · Profit factor per bot (gross wins / gross losses).
SELECT
    bot,
    ROUND(
        SUM(CASE WHEN pnl > 0 THEN pnl ELSE 0 END)
        / NULLIF(ABS(SUM(CASE WHEN pnl < 0 THEN pnl ELSE 0 END)), 0)
    , 2) AS profit_factor
FROM trades
WHERE closed_at IS NOT NULL AND is_manual = FALSE
GROUP BY bot;

-- Q4 · Running equity curve — cumulative P&L per bot (window function).
SELECT
    bot,
    trade_id,
    closed_at,
    pnl,
    SUM(pnl) OVER (PARTITION BY bot ORDER BY closed_at) AS equity_curve
FROM trades
WHERE closed_at IS NOT NULL
ORDER BY bot, closed_at;

-- Q5 · Worst drawdown window — peak-to-trough per bot (CTE + window).
WITH curve AS (
    SELECT bot, closed_at,
           SUM(pnl) OVER (PARTITION BY bot ORDER BY closed_at) AS equity
    FROM trades
    WHERE closed_at IS NOT NULL AND is_manual = FALSE
),
peaks AS (
    SELECT bot, closed_at, equity,
           MAX(equity) OVER (PARTITION BY bot ORDER BY closed_at) AS running_peak
    FROM curve
)
SELECT bot,
       MIN(equity - running_peak) AS worst_drawdown_amount
FROM peaks
GROUP BY bot;

-- Q6 · Signal quality — do high-strength signals actually win more?
SELECT
    CASE WHEN s.strength >= 0.80 THEN '0.80–1.00'
         WHEN s.strength >= 0.60 THEN '0.60–0.79'
         ELSE 'below 0.60' END                          AS strength_band,
    COUNT(*)                                            AS taken_trades,
    ROUND(AVG(t.r_multiple), 2)                         AS avg_r
FROM signals s
JOIN trades t
  ON t.bot = s.bot AND t.strategy = s.strategy
 AND t.opened_at >= s.generated_at
WHERE s.decision = 'TAKEN' AND t.closed_at IS NOT NULL
GROUP BY strength_band
ORDER BY strength_band DESC;

-- Q7 · Veto audit — what did the vetoes save us from? (count by reason)
SELECT
    veto_reason,
    COUNT(*) AS vetoed_signals
FROM signals
WHERE decision = 'VETOED'
GROUP BY veto_reason
ORDER BY vetoed_signals DESC;

-- Q8 · ADX gate check — win rate above vs below the trend gate (ADX 20).
SELECT
    CASE WHEN s.adx >= 20 THEN 'ADX >= 20 (gate pass)'
         ELSE 'ADX < 20 (gate should have blocked)' END AS gate_band,
    COUNT(*)                                            AS trades,
    ROUND(100.0 * AVG(CASE WHEN t.pnl > 0 THEN 1 ELSE 0 END), 1) AS win_rate_pct
FROM signals s
JOIN trades t
  ON t.bot = s.bot AND t.opened_at >= s.generated_at
WHERE s.decision = 'TAKEN' AND t.closed_at IS NOT NULL
GROUP BY gate_band;

-- Q9 · Risk-rail audit — every halt/kill event, newest first.
SELECT
    bot, event_type, occurred_at, equity, detail
FROM risk_events
ORDER BY occurred_at DESC;

-- Q10 · Daily P&L with the 2% halt line — did any day breach it?
WITH daily AS (
    SELECT bot,
           DATE(closed_at)              AS day,
           SUM(pnl)                     AS day_pnl
    FROM trades
    WHERE closed_at IS NOT NULL AND is_manual = FALSE
    GROUP BY bot, DATE(closed_at)
)
SELECT d.bot, d.day, d.day_pnl,
       CASE WHEN EXISTS (
           SELECT 1 FROM risk_events r
           WHERE r.bot = d.bot
             AND r.event_type = 'DAILY_HALT'
             AND DATE(r.occurred_at) = d.day
       ) THEN 'HALT FIRED' ELSE 'within rails' END AS rail_status
FROM daily d
ORDER BY d.day DESC, d.bot;
