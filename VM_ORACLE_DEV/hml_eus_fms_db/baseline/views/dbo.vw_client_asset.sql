CREATE      VIEW [dbo].[vw_client_asset] AS

WITH period AS (
    SELECT
        MAX(process_date)                        AS ref_date,
        DATEADD(MONTH, -6, MAX(process_date))    AS start_date
    FROM dbo.tb_client_daily_profile
),
asset_volume AS (
    SELECT
        cdp.account,
        cdp.symbol,
        SUM(cdp.total_financial_volume) AS asset_volume,
        SUM(cdp.buy_volume)             AS asset_buy_volume,
        SUM(cdp.sell_volume)            AS asset_sell_volume,
        SUM(cdp.trade_count)            AS asset_trade_count,
        MIN(cdp.process_date)           AS first_traded,
        MAX(cdp.process_date)           AS last_traded,
        COUNT(DISTINCT cdp.process_date) AS active_days
    FROM dbo.tb_client_daily_profile cdp
    CROSS JOIN period p
    WHERE cdp.process_date BETWEEN p.start_date AND p.ref_date
    GROUP BY cdp.account, cdp.symbol
)
SELECT
    a.account,
    a.symbol,

    -- ?? Volume ????????????????????????????????????????????????
    a.asset_volume,
    a.asset_buy_volume,
    a.asset_sell_volume,
    a.asset_trade_count,

    -- ?? Volume total do cliente (todos os ativos no período) ??
    SUM(a.asset_volume) OVER (PARTITION BY a.account)           AS client_total_volume,

    -- ?? Concentração ?????????????????????????????????????????
    ISNULL(
        a.asset_volume
        / NULLIF(SUM(a.asset_volume) OVER (PARTITION BY a.account), 0) * 100
    , 0)                                                        AS concentration_pct,

    -- ?? Ranking do ativo dentro do cliente ???????????????????
    RANK() OVER (
        PARTITION BY a.account
        ORDER BY a.asset_volume DESC
    )                                                           AS asset_rank,

    -- ?? Atividade ?????????????????????????????????????????????
    a.active_days,
    a.first_traded,
    a.last_traded

FROM asset_volume a;