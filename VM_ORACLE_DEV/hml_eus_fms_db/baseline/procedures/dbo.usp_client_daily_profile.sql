CREATE   PROCEDURE  [dbo].[usp_client_daily_profile]
AS
--/*
--Descricao de alteracoes

--Dia: 22/05/2026 - Alteracao
--predominant_time_window alterado de faixas textuais (Morning/Midday/Afternoon)
--para intervalo de hora no formato 'HH:00-HH:00'. Criterio de predominancia
--alterado de maior volume financeiro para maior quantidade de negocios (COUNT).

--Dia: 21/05/2026 - Guimo
--Criacao da procedure de perfil diario por cliente e ativo.
--Granularidade: process_date + account + symbol.
--Consolida ordens, volume, temporalidade, contrapartes
--e alertas. Detalhe de contrapartes em tb_client_counterparty.
--Segue o padrao de log e reprocessamento do projeto.

--Dia: 04/08/2026 - Guimo e Gobbo
--Tratamento dos mini indices 
--quando 'WIN%' multiplicado volume  por * 0.20
--quando 'WDO%' multiplicado volume  por * 10.00
--quando 'BIT%' multiplicado volume  por * 0.10

--Dia: 04/08/2026 - Guimo e Gobbo
--Inclusao das colunas total_orders_modify e modify_rate_pct
--(quantidade e percentual de ordens modificadas/replace, exec_type = '5')

--*/
------------------------------------------------------------
-- Declaracao das variaveis de log
------------------------------------------------------------
DECLARE @LogID             INT;
DECLARE @log_process_date  DATE = (SELECT MAX(process_date) FROM tb_order);


BEGIN TRY

    INSERT INTO log_ms (process, dt_exec, dt_begin, status_description, process_date)
    VALUES ('ClientDailyProfile', GETDATE(), GETDATE(), 'Started', @log_process_date);
    SET @LogID = SCOPE_IDENTITY();

    IF (SELECT COUNT(1) FROM log_ms
         WHERE process      = 'ClientDailyProfile'
           AND process_date = @log_process_date) > 0
    BEGIN
        PRINT 'reprocessing...'
        DELETE FROM tb_client_daily_profile
         WHERE process_date = @log_process_date;

        DELETE FROM tb_client_counterparty WHERE process_date = @log_process_date;
    END
    ELSE
    BEGIN
        PRINT 'processing...'
    END

------------------------------------------------------------
-- CLIENT DAILY PROFILE >>>>> INICIO
------------------------------------------------------------


    --------------------------------------------------------
    -- Temp 1: base bruta - entrypoint x trades
    --------------------------------------------------------
    DROP TABLE IF EXISTS #base;

    SELECT
        CAST(d.process_date    AS DATE)         AS process_date,
        CAST(d.account         AS VARCHAR(50))  AS account,
        d.symbol,
        d.order_id,
        d.side,
        d.ord_status,
        d.exec_type,
        ISNULL(CAST(d.lastqty  AS DECIMAL(18,4)), 0) AS last_qty,
        ISNULL(CAST(d.last_px  AS DECIMAL(18,4)), 0) AS last_px,
        CAST(d.order_timestamp AS DATETIME2)         AS transact_time_br,

        CASE
            WHEN t.broker_buy  IS NULL THEN NULL
            WHEN d.side = 1 THEN CAST(t.broker_sell AS VARCHAR(100))
            WHEN d.side = 2 THEN CAST(t.broker_buy  AS VARCHAR(100))
        END AS counterparty,

        CASE WHEN t.direct = 1 THEN 1 ELSE 0 END AS is_direct
        

    INTO #base
    FROM dbo.tb_entrypoint d
    left JOIN dbo.tb_trade t
        ON  d.symbol   = t.symbol
        AND d.trade_id = t.trade_id
    WHERE CAST(d.process_date AS DATE) = @log_process_date and account is not null; 


    --------------------------------------------------------
    -- Temp 2: agregacao - 1 linha por cliente/ativo/dia
    --------------------------------------------------------
    DROP TABLE IF EXISTS #aggregated;

    SELECT
        process_date,
        account,
        symbol,

        COUNT(DISTINCT order_id)                                                            AS total_orders_sent,
        COUNT(DISTINCT CASE WHEN exec_type = 'F'  THEN order_id END)                       AS total_orders_executed,
        COUNT(DISTINCT CASE WHEN exec_type = '4'  THEN order_id END)                       AS total_orders_cancelled,
        COUNT(DISTINCT CASE WHEN ord_status = '8'   THEN order_id END)                       AS total_orders_rejected,

         CASE
            WHEN symbol LIKE 'WIN%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' THEN last_qty * last_px END), 0) * 0.20
            WHEN symbol LIKE 'WDO%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' THEN last_qty * last_px END), 0)* 10.00
            WHEN symbol LIKE 'BIT%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' THEN last_qty * last_px END), 0) * 0.10
            ELSE ISNULL(SUM(CASE WHEN exec_type = 'F'              THEN last_qty * last_px END), 0)  -- demais ativos mantêm o original
        END AS total_financial_volume,

        --ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 1 THEN last_qty * last_px END), 0) AS buy_volume,
		CASE
            WHEN symbol LIKE 'WIN%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 1 THEN last_qty * last_px END), 0) * 0.20
            WHEN symbol LIKE 'WDO%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 1 THEN last_qty * last_px END), 0)* 10.00
            WHEN symbol LIKE 'BIT%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 1 THEN last_qty * last_px END), 0) * 0.10
            ELSE ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 1 THEN last_qty * last_px END), 0)  -- demais ativos mantêm o original
        END buy_volume,

        --ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 2 THEN last_qty * last_px END), 0) AS sell_volume,
		CASE
            WHEN symbol LIKE 'WIN%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 2 THEN last_qty * last_px END), 0) * 0.20
            WHEN symbol LIKE 'WDO%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 2 THEN last_qty * last_px END), 0)* 10.00
            WHEN symbol LIKE 'BIT%' THEN ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 2 THEN last_qty * last_px END), 0) * 0.10
            ELSE ISNULL(SUM(CASE WHEN exec_type = 'F' AND side = 2 THEN last_qty * last_px END), 0)  -- demais ativos mantêm o original
        END sell_volume,

        SUM(CASE WHEN exec_type = 'F' THEN 1 ELSE 0 END)                                   AS trade_count,

        MIN(CASE WHEN exec_type = 'F' THEN transact_time_br END)                           AS first_trade_time,
        MAX(CASE WHEN exec_type = 'F' THEN transact_time_br END)                           AS last_trade_time,

        SUM(CASE WHEN exec_type = 'F' THEN is_direct ELSE 0 END)                           AS total_direct,

        COUNT(DISTINCT CASE WHEN exec_type = '5'  THEN order_id END)                       AS total_orders_modify

    INTO #aggregated
    FROM #base
    GROUP BY process_date, account, symbol;

	


    --------------------------------------------------------
    -- Temp 3: contrapartes por cliente/ativo/dia (todas)
    --------------------------------------------------------
    DROP TABLE IF EXISTS #counterparties;

    SELECT
        process_date,
        account,
        symbol,
        counterparty,
        --SUM(last_qty * last_px) AS volume
		
		CASE
            WHEN symbol LIKE 'WIN%' THEN SUM(last_qty * last_px) * 0.20
            WHEN symbol LIKE 'WDO%' THEN SUM(last_qty * last_px)* 10.00
            WHEN symbol LIKE 'BIT%' THEN SUM(last_qty * last_px) * 0.10
            ELSE SUM(last_qty * last_px)  -- demais ativos mantêm o original
        END AS volume

    INTO #counterparties
    FROM #base
    WHERE exec_type    = 'F'
      AND counterparty IS NOT NULL
    GROUP BY process_date, account, symbol, counterparty;


    --------------------------------------------------------
    -- Temp 4: contagem de alertas por cliente/ativo/dia
    --------------------------------------------------------
    DROP TABLE IF EXISTS #alerts;

    SELECT
        account,
        symbol,
        date,
        COUNT(1) AS alert_count
    INTO #alerts
    FROM dbo.issues
    WHERE date = @log_process_date
    GROUP BY account, symbol, date;

    --------------------------------------------------------
    -- Insert 1: tb_client_daily_profile
    --------------------------------------------------------
    INSERT INTO dbo.tb_client_daily_profile (
        process_date,
        account,
        symbol,
        total_orders_sent,
        total_orders_executed,
        total_orders_cancelled,
        total_orders_rejected,
        cancel_rate_pct,
        execution_rate_pct,
        total_financial_volume,
        buy_volume,
        sell_volume,
        buy_sell_ratio,
        trade_count,
        avg_ticket,
        predominant_time_window,
        first_trade_time,
        last_trade_time,
        main_counterparty,
        direct_trades_pct,
        total_alerts_day,
        created_at,
        total_orders_modify,
        modify_rate_pct
    )
    SELECT
        a.process_date,
        a.account,
        a.symbol,

        a.total_orders_sent,
        a.total_orders_executed,
        a.total_orders_cancelled,
        a.total_orders_rejected,

        ISNULL(CAST(a.total_orders_cancelled AS DECIMAL(18,4))
               / NULLIF(a.total_orders_sent, 0) * 100, 0)              AS cancel_rate_pct,
        ISNULL(CAST(a.total_orders_executed  AS DECIMAL(18,4))
               / NULLIF(a.total_orders_sent, 0) * 100, 0)              AS execution_rate_pct,

        a.total_financial_volume,
        a.buy_volume,
        a.sell_volume,

        ISNULL(a.buy_volume / NULLIF(a.sell_volume, 0), 1.0)           AS buy_sell_ratio,
        a.trade_count,
        ISNULL(a.total_financial_volume / NULLIF(a.trade_count, 0), 0) AS avg_ticket,

        top_time.window_name                                            AS predominant_time_window,
        CAST(a.first_trade_time AS TIME)                                AS first_trade_time,
        CAST(a.last_trade_time  AS TIME)                                AS last_trade_time,

        top_cp.counterparty                                             AS main_counterparty,

        ISNULL(CAST(a.total_direct AS DECIMAL(18,4))
               / NULLIF(a.trade_count, 0) * 100, 0)                    AS direct_trades_pct,


        ISNULL(al.alert_count, 0)                                       AS total_alerts_day,
        GETDATE()                                                       AS created_at,

        a.total_orders_modify,
        ISNULL(CAST(a.total_orders_modify AS DECIMAL(18,4))
               / NULLIF(a.total_orders_sent, 0) * 100, 0)              AS modify_rate_pct
		
    FROM #aggregated a

    OUTER APPLY (
        SELECT TOP 1
            RIGHT('0' + CAST(DATEPART(HOUR, transact_time_br)     AS VARCHAR(2)), 2) + ':00-' +
            RIGHT('0' + CAST(DATEPART(HOUR, transact_time_br) + 1 AS VARCHAR(2)), 2) + ':00'
                AS window_name
        FROM #base b_time
        WHERE b_time.account      = a.account
          AND b_time.process_date = a.process_date
          AND b_time.symbol       = a.symbol
          AND b_time.exec_type    = 'F'
        GROUP BY DATEPART(HOUR, transact_time_br)
        ORDER BY COUNT(1) DESC
    ) top_time

    OUTER APPLY (
        SELECT TOP 1 counterparty
        FROM #counterparties c_top
        WHERE c_top.account      = a.account
          AND c_top.process_date = a.process_date
          AND c_top.symbol       = a.symbol
        ORDER BY volume DESC
    ) top_cp

    LEFT JOIN #alerts al
        ON  al.account      = a.account
        AND al.symbol       = a.symbol
        AND al.date         = a.process_date;


    --------------------------------------------------------
    -- Insert 2: tb_client_counterparty
    -- Inserido apos o pai para respeitar a FK
    --------------------------------------------------------
    INSERT INTO dbo.tb_client_counterparty (
        process_date,
        account,
        symbol,
        counterparty,
        volume,
        created_at
    )
    SELECT
        process_date,
        account,
        symbol,
        counterparty,
        volume,
        GETDATE()
    FROM #counterparties;



--------------------------------------------------------
 --CLIENT DAILY PROFILE >>>>> FIM
--------------------------------------------------------

    UPDATE log_ms
       SET dt_end             = GETDATE()
         , duration           = CAST(GETDATE() - dt_begin AS TIME)
         , status_description = 'Completed'
     WHERE id_log = @LogID;

END TRY
BEGIN CATCH

    DECLARE @ERROR_MSG VARCHAR(1000) = ERROR_MESSAGE();

    UPDATE log_ms
       SET dt_end             = GETDATE()
         , duration           = CAST(GETDATE() - dt_begin AS TIME)
         , status_description = 'Error: ' + ERROR_MESSAGE()
     WHERE id_log = @LogID;

    RAISERROR(@ERROR_MSG, 16, 1);

END CATCH;