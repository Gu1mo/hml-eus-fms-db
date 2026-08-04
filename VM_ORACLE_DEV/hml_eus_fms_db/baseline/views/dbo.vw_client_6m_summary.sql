CREATE     VIEW [dbo].[vw_client_6m_summary] AS
WITH period AS (
    -- Janela de 6 meses a partir da data mais recente disponível
    SELECT
        MAX(process_date)                        AS ref_date,
        DATEADD(MONTH, -6, MAX(process_date))    AS start_date
    FROM dbo.tb_client_daily_profile 
),
base AS (
 SELECT
        cdp.process_date,
        cdp.account,
        cdp.symbol,
        cdp.total_orders_sent,
        cdp.total_orders_executed,
        cdp.total_orders_cancelled,
        cdp.total_orders_rejected,
        cdp.total_orders_modify,
       -- cdp.total_financial_volume,          -- original
        cdp.buy_volume,
        cdp.sell_volume,
        cdp.trade_count,
        cdp.predominant_time_window,
        cdp.direct_trades_pct,
        cdp.rlp_trades_pct,
        cdp.total_alerts_day,
        p.start_date,
        p.ref_date,
        -- Volume ajustado por símbolo (aplicado ANTES da soma)
        CASE
            WHEN cdp.symbol LIKE 'WIN%' THEN cdp.total_financial_volume * 0.20
            WHEN cdp.symbol LIKE 'WDO%' THEN cdp.total_financial_volume * 10.00
            WHEN cdp.symbol LIKE 'BIT%' THEN cdp.total_financial_volume * 0.10
            ELSE cdp.total_financial_volume  -- demais ativos mantêm o original
        END AS total_financial_volume
    FROM dbo.tb_client_daily_profile cdp
    CROSS JOIN period p
    WHERE cdp.process_date BETWEEN p.start_date AND p.ref_date
),
-- Contraparte mais frequente no período (por volume total)
top_counterparty AS (
    SELECT
        ccp.account,
        ccp.counterparty,
        SUM(ccp.volume) AS cp_volume,
        ROW_NUMBER() OVER (PARTITION BY ccp.account ORDER BY SUM(ccp.volume) DESC) AS rn
    FROM dbo.tb_client_counterparty ccp
    CROSS JOIN period p
    WHERE ccp.process_date BETWEEN p.start_date AND p.ref_date
    GROUP BY ccp.account, ccp.counterparty
)
SELECT
    -- ?? Identificação ?????????????????????????????????????????
    b.account,
    b.start_date                                                AS period_start,
    b.ref_date                                                  AS period_end,

    -- ?? Atividade ?????????????????????????????????????????????
    COUNT(DISTINCT b.process_date)                              AS active_days,
    COUNT(DISTINCT CASE WHEN b.total_orders_executed > 0 THEN b.symbol END)  AS distinct_assets,

    -- ?? Comportamento de ordens ???????????????????????????????
    SUM(b.total_orders_sent)                                    AS total_orders_sent,
    SUM(b.total_orders_executed)                                AS total_orders_executed,
    SUM(b.total_orders_cancelled)                               AS total_orders_cancelled,
    SUM(b.total_orders_rejected)                                AS total_orders_rejected,
    SUM(b.total_orders_modify)                                  AS total_orders_modify,

    ISNULL(
        CAST(SUM(b.total_orders_cancelled) AS DECIMAL(18,4))
        / NULLIF(SUM(b.total_orders_sent), 0) * 100
    , 0)                                                        AS cancel_rate_pct,
    ISNULL(
        CAST(SUM(b.total_orders_executed) AS DECIMAL(18,4))
        / NULLIF(SUM(b.total_orders_sent), 0) * 100
    , 0)                                                        AS execution_rate_pct,
    ISNULL(
        CAST(SUM(b.total_orders_modify) AS DECIMAL(18,4))
        / NULLIF(SUM(b.total_orders_sent), 0) * 100
    , 0)                                                        AS modify_rate_pct,

    -- ?? Volume & Negociação ???????????????????????????????????
    SUM(b.total_financial_volume)                               AS total_financial_volume,----aqui



    SUM(b.buy_volume)                                           AS total_buy_volume,
    SUM(b.sell_volume)                                          AS total_sell_volume,
    ISNULL(
        SUM(b.buy_volume) / NULLIF(SUM(b.sell_volume), 0)
    , 1.0)                                                      AS buy_sell_ratio,
    SUM(b.trade_count)                                          AS total_trades,
    ISNULL(
        SUM(b.total_financial_volume) / NULLIF(SUM(b.trade_count), 0)
    , 0)                                                        AS avg_ticket,

    -- ?? Horário predominante (janela com maior volume no período)
    (
        SELECT TOP 1 bb.predominant_time_window
        FROM base bb
        WHERE bb.account = b.account
          AND bb.predominant_time_window IS NOT NULL
        GROUP BY bb.predominant_time_window
        ORDER BY SUM(bb.total_financial_volume) DESC
    )                                                           AS predominant_time_window,

    -- ?? Contraparte principal no período ?????????????????????
    tc.counterparty                                             AS main_counterparty_6m,

    -- ?? Negocios Diretos / RLP ????????????????????????????????
    ISNULL(
        CAST(SUM(CASE WHEN b.direct_trades_pct > 0
                      THEN b.trade_count * b.direct_trades_pct / 100.0
                      ELSE 0 END) AS DECIMAL(18,4))
        / NULLIF(SUM(b.trade_count), 0) * 100
    , 0)                                                        AS direct_trades_pct,
    ISNULL(
        CAST(SUM(CASE WHEN b.rlp_trades_pct > 0
                      THEN b.trade_count * b.rlp_trades_pct / 100.0
                      ELSE 0 END) AS DECIMAL(18,4))
        / NULLIF(SUM(b.trade_count), 0) * 100
    , 0)                                                        AS rlp_trades_pct,

    -- ?? Alertas ???????????????????????????????????????????????
    SUM(b.total_alerts_day)                                     AS total_alerts,
    COUNT(DISTINCT CASE WHEN b.total_alerts_day > 0
                        THEN b.process_date END)                AS days_with_alerts,
    ISNULL(
        CAST(COUNT(DISTINCT CASE WHEN b.total_alerts_day > 0
                                 THEN b.process_date END) AS DECIMAL(18,4))
        / NULLIF(COUNT(DISTINCT b.process_date), 0) * 100
    , 0)                                                        AS alert_recurrence_pct

FROM base b
LEFT JOIN top_counterparty tc
    ON  tc.account = b.account
    AND tc.rn      = 1
GROUP BY
    b.account,
    b.start_date,
    b.ref_date,
    tc.counterparty;