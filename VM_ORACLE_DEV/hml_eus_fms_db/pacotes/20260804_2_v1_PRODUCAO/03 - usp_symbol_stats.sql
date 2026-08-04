
ALTER   PROCEDURE [dbo].[usp_symbol_stats]
AS
/*
-- Descricao de alteracoes

-- Dia: 30/06/2026 - Criacao
-- Processo diario de consolidacao de estatisticas por ativo (symbol).
-- Granularidade: process_date + symbol (1 linha por ativo por pregao).
-- Fontes:
--   tb_trade          -> negocios internos do dia
--   tb_quote          -> cotacoes e volume de mercado
--   tb_entrypoint     -> clientes e execucoes da corretora
--   FatosRelevantes   -> quantidade de fatos relevantes publicados no dia
-- Tabelas populadas:
--   tb_symbol_stats             (1 por ativo/dia)
--   tb_symbol_stats_top_clients (top 5 clientes por ativo/dia)
--   tb_symbol_stats_top_brokers (top 5 corretoras por ativo/dia)
--   tb_symbol_stats_time_windows (volume por janela horaria)
--   tb_symbol_stats_price_chart  (OHLC de 5 min para grafico)
-- Segue o padrao de log e reprocessamento do projeto.

--Dia: 04/08/2026 - Guimo e Gobbo
--Tratamento dos mini indices 
--quando 'WIN%' multiplicado volume  por * 0.20
--quando 'WDO%' multiplicado volume  por * 10.00
--quando 'BIT%' multiplicado volume  por * 0.10
*/

-- ----------------------------------------------------------------
-- Declaracao das variaveis de log
-- ----------------------------------------------------------------
DECLARE @LogID              INT;
DECLARE @log_process_date   DATE        = (SELECT MAX(process_date) FROM dbo.tb_trade);
DECLARE @party_id           VARCHAR(50) = (SELECT MAX(party_id) FROM dbo.tb_party_id);

BEGIN TRY

    INSERT INTO log_ms (process, dt_exec, dt_begin, status_description, process_date)
    VALUES ('SymbolStats', GETDATE(), GETDATE(), 'Started', @log_process_date);
    SET @LogID = SCOPE_IDENTITY();

    -- Reprocessamento: > 1 pois o INSERT acima ja cria 1 registro
    IF (SELECT COUNT(1) FROM log_ms
          WHERE process       = 'SymbolStats'
            AND process_date  = @log_process_date) > 1
    BEGIN
        PRINT 'reprocessing...';
        DELETE FROM dbo.tb_symbol_stats             WHERE process_date = @log_process_date;
        DELETE FROM dbo.tb_symbol_stats_top_clients WHERE process_date = @log_process_date;
        DELETE FROM dbo.tb_symbol_stats_top_brokers WHERE process_date = @log_process_date;
        DELETE FROM dbo.tb_symbol_stats_time_windows WHERE process_date = @log_process_date;
        DELETE FROM dbo.tb_symbol_stats_price_chart  WHERE process_date = @log_process_date;
    END
    ELSE
    BEGIN
        PRINT 'processing...';
    END


-- ----------------------------------------------------------------
-- SYMBOL STATS >>>>> INICIO
-- ----------------------------------------------------------------


    -- ----------------------------------------------------------------
    -- Temp 1: todos os trades do dia com broker_buy/broker_sell
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #trades_base;

    SELECT
        CAST(t.process_date AS DATE)                                    AS process_date,
        t.symbol,
        t.trade_id,
        CAST(t.price    AS DECIMAL(18,4))                               AS price,
        CAST(t.quantity AS DECIMAL(18,4))                               AS quantity,
        CAST(t.price    AS DECIMAL(18,4))
            * CAST(t.quantity AS DECIMAL(18,4))                         AS trade_value,
        CAST(t.trade_time AS TIME)                                      AS trade_time,
        t.broker_buy,
        t.broker_sell
    INTO #trades_base
    FROM dbo.tb_trade t
    WHERE CAST(t.process_date AS DATE) = @log_process_date;


    -- ----------------------------------------------------------------
    -- Temp 2: agregacoes por simbolo
    --   broker_*  = apenas trades da corretora (CASE WHEN @party_id)
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #trade_agg;

    SELECT
        tb.process_date,
        tb.symbol,
        --SUM(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.trade_value ELSE 0 END)   AS broker_volume,
		 
		 CASE
            WHEN tb.symbol LIKE 'WIN%' THEN SUM(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.trade_value ELSE 0 END) * 0.20
            WHEN tb.symbol LIKE 'WDO%' THEN SUM(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.trade_value ELSE 0 END) * 10.00
            WHEN tb.symbol LIKE 'BIT%' THEN SUM(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.trade_value ELSE 0 END) * 0.10
            ELSE SUM(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.trade_value ELSE 0 END)  -- demais ativos mantêm o original
        END AS broker_volume,

        SUM(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.quantity  ELSE 0 END)     AS broker_qty,
        COUNT(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN 1 END)                     AS broker_trade_count,
        AVG(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.price END)                AS broker_trade_value_avg,
        MIN(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.price END)                AS broker_trade_value_min,
        MAX(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.price END)                AS broker_trade_value_max,
        AVG(CASE WHEN tb.broker_buy = @party_id OR tb.broker_sell = @party_id THEN tb.quantity END)             AS broker_avg_quantity
    INTO #trade_agg
    FROM #trades_base tb
    GROUP BY tb.process_date, tb.symbol;


    -- ----------------------------------------------------------------
    -- Temp 3: primeiro e ultimo trade da corretora no pregao
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #trade_open_close;

    ;WITH broker_ranked AS (
        SELECT
            process_date,
            symbol,
            price,
            ROW_NUMBER() OVER (PARTITION BY process_date, symbol
                               ORDER BY trade_id ASC,  trade_time ASC)  AS rn_open,
            ROW_NUMBER() OVER (PARTITION BY process_date, symbol
                               ORDER BY trade_id DESC, trade_time DESC) AS rn_close
        FROM #trades_base
        WHERE broker_buy = @party_id OR broker_sell = @party_id
    )
    SELECT
        o.process_date,
        o.symbol,
        o.price         AS broker_trade_value_open,
        c.price         AS broker_trade_value_close
    INTO #trade_open_close
    FROM broker_ranked o
    JOIN broker_ranked c
        ON  c.symbol       = o.symbol
        AND c.process_date = o.process_date
        AND c.rn_close     = 1
    WHERE o.rn_open = 1;


    -- ----------------------------------------------------------------
    -- Temp 4: quantidade total negociada no mercado por simbolo
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #market_qty;

    SELECT
        process_date,
        symbol,
        SUM(quantity)   AS market_qty
    INTO #market_qty
    FROM #trades_base
    GROUP BY process_date, symbol;


    -- ----------------------------------------------------------------
    -- Temp 5: quantidade executada pela corretora (tb_entrypoint)
    -- Usado somente para broker_market_share_pct
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #broker_qty;

    SELECT
        CAST(ep.process_date AS DATE)               AS process_date,
        ep.symbol,
        SUM(CAST(ep.lastqty AS DECIMAL(18,4)))       AS broker_qty
    INTO #broker_qty
    FROM dbo.tb_entrypoint ep
    WHERE CAST(ep.process_date AS DATE) = @log_process_date
      AND ep.exec_type = 'F'
      AND ep.lastqty   IS NOT NULL
    GROUP BY CAST(ep.process_date AS DATE), ep.symbol;


    -- ----------------------------------------------------------------
    -- Temp 6: Fatos Relevantes publicados no dia
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #relevant_facts;

    SELECT
        fr.Ativo        AS symbol,
        COUNT(1)        AS relevant_facts_count
    INTO #relevant_facts
    FROM dbo.FatosRelevantes fr
    WHERE CAST(fr.Data AS DATE) = @log_process_date
    GROUP BY fr.Ativo;


    -- ----------------------------------------------------------------
    -- Temp 7: clientes da corretora por simbolo (tb_entrypoint)
    -- Fonte para distinct_client_count e top 5 clientes
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #client_agg;

    SELECT
        CAST(ep.process_date AS DATE)                                           AS process_date,
        ep.symbol,
        CAST(ep.account AS VARCHAR(50))                                         AS account,
        
		
		--SUM(CAST(ep.lastqty AS DECIMAL(18,4)) * CAST(ep.last_px AS DECIMAL(18,4))) AS client_volume,

		 CASE
            WHEN ep.symbol LIKE 'WIN%' THEN SUM(CAST(ep.lastqty AS DECIMAL(18,4)) * CAST(ep.last_px AS DECIMAL(18,4))) * 0.20
            WHEN ep.symbol LIKE 'WDO%' THEN SUM(CAST(ep.lastqty AS DECIMAL(18,4)) * CAST(ep.last_px AS DECIMAL(18,4))) * 10.00
            WHEN ep.symbol LIKE 'BIT%' THEN SUM(CAST(ep.lastqty AS DECIMAL(18,4)) * CAST(ep.last_px AS DECIMAL(18,4))) * 0.10
            ELSE SUM(CAST(ep.lastqty AS DECIMAL(18,4)) * CAST(ep.last_px AS DECIMAL(18,4)))  -- demais ativos mantêm o original
        END AS client_volume,


        SUM(CAST(ep.lastqty AS DECIMAL(18,4)))                                  AS client_qty,
        COUNT(1)                                                                AS client_trade_count
    INTO #client_agg
    FROM dbo.tb_entrypoint ep
    WHERE CAST(ep.process_date AS DATE) = @log_process_date
      AND ep.exec_type = 'F'
      AND ep.account   IS NOT NULL
    GROUP BY CAST(ep.process_date AS DATE), ep.symbol, CAST(ep.account AS VARCHAR(50));


    -- ----------------------------------------------------------------
    -- Temp 8: contagem de clientes distintos por simbolo
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #client_summary;

    SELECT
        process_date,
        symbol,
        COUNT(1)        AS distinct_client_count
    INTO #client_summary
    FROM #client_agg
    GROUP BY process_date, symbol;


    -- ----------------------------------------------------------------
    -- Temp 9: todas as corretoras que negociaram cada simbolo
    -- Cada trade contribui volume para o lado comprador e vendedor
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #broker_agg;

    ;WITH broker_sides AS (
        SELECT process_date, symbol, CAST(broker_buy  AS VARCHAR(50)) AS broker_id, trade_value
        FROM #trades_base WHERE broker_buy  IS NOT NULL
        UNION ALL
        SELECT process_date, symbol, CAST(broker_sell AS VARCHAR(50)) AS broker_id, trade_value
        FROM #trades_base WHERE broker_sell IS NOT NULL
    )
    SELECT
        process_date,
        symbol,
        broker_id,
        SUM(trade_value)    AS broker_volume,
        COUNT(1)            AS broker_trade_count
    INTO #broker_agg
    FROM broker_sides
    GROUP BY process_date, symbol, broker_id;


    -- ----------------------------------------------------------------
    -- Temp 10: contagem de corretoras distintas por simbolo
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #broker_summary;

    SELECT
        process_date,
        symbol,
        COUNT(1)        AS distinct_broker_count
    INTO #broker_summary
    FROM #broker_agg
    GROUP BY process_date, symbol;


    -- ----------------------------------------------------------------
    -- Temp 11: volume e negocios por janela horaria (1 hora)
    -- Mesma logica de janela do usp_client_daily_profile
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #time_windows_agg;

    SELECT
        process_date,
        symbol,
        RIGHT('0' + CAST(DATEPART(HOUR, trade_time) AS VARCHAR(2)), 2) + ':00-' +
        RIGHT('0' + CAST(DATEPART(HOUR, trade_time) + 1 AS VARCHAR(2)), 2) + ':00'  AS time_window,
        SUM(trade_value)    AS window_volume,
        COUNT(1)            AS window_trade_count
    INTO #time_windows_agg
    FROM #trades_base
    GROUP BY process_date, symbol, DATEPART(HOUR, trade_time);


    -- ----------------------------------------------------------------
    -- Temp 12: janela horaria com maior volume por simbolo
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #peak_volume_window;

    ;WITH ranked_windows AS (
        SELECT
            process_date,
            symbol,
            time_window,
            ROW_NUMBER() OVER (PARTITION BY process_date, symbol ORDER BY window_volume DESC) AS rn
        FROM #time_windows_agg
    )
    SELECT process_date, symbol, time_window AS peak_volume_window
    INTO #peak_volume_window
    FROM ranked_windows
    WHERE rn = 1;


    -- ----------------------------------------------------------------
    -- Temp 13: duracao da sessao por simbolo (para negocios/minuto)
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #session_duration;

    SELECT
        process_date,
        symbol,
        DATEDIFF(MINUTE, MIN(trade_time), MAX(trade_time))  AS session_minutes
    INTO #session_duration
    FROM #trades_base
    GROUP BY process_date, symbol;


    -- ----------------------------------------------------------------
    -- Temp 14: OHLC de 5 minutos por simbolo (para grafico de preco)
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #price_chart;

    ;WITH chart_intervals AS (
        SELECT
            process_date,
            symbol,
            TIMEFROMPARTS(
                DATEPART(HOUR, trade_time),
                (DATEPART(MINUTE, trade_time) / 5) * 5,
                0, 0, 0
            )                                                               AS interval_start,
            price,
            trade_value,
            trade_id,
            trade_time,
            ROW_NUMBER() OVER (
                PARTITION BY process_date, symbol,
                    TIMEFROMPARTS(DATEPART(HOUR, trade_time), (DATEPART(MINUTE, trade_time) / 5) * 5, 0, 0, 0)
                ORDER BY trade_id ASC, trade_time ASC
            )                                                               AS rn_open,
            ROW_NUMBER() OVER (
                PARTITION BY process_date, symbol,
                    TIMEFROMPARTS(DATEPART(HOUR, trade_time), (DATEPART(MINUTE, trade_time) / 5) * 5, 0, 0, 0)
                ORDER BY trade_id DESC, trade_time DESC
            )                                                               AS rn_close
        FROM #trades_base
    )
    SELECT
        ci.process_date,
        ci.symbol,
        ci.interval_start,
        MAX(CASE WHEN ci.rn_open  = 1 THEN ci.price END)   AS open_price,
        MAX(ci.price)                                        AS high_price,
        MIN(ci.price)                                        AS low_price,
        MAX(CASE WHEN ci.rn_close = 1 THEN ci.price END)   AS close_price,
        SUM(ci.trade_value)                                  AS volume,
        COUNT(1)                                             AS trade_count
    INTO #price_chart
    FROM chart_intervals ci
    GROUP BY ci.process_date, ci.symbol, ci.interval_start;


    -- ----------------------------------------------------------------
    -- Temp 15: media e desvio historico por simbolo (30 pregoes)
    -- Usado para detectar atipicidade no dia atual
    -- ----------------------------------------------------------------
    DROP TABLE IF EXISTS #hist_stats;

    SELECT
        symbol,
        AVG(CAST(market_volume      AS FLOAT))          AS avg_volume,
        STDEV(CAST(market_volume    AS FLOAT))          AS stdev_volume,
        AVG(CAST(market_trade_count AS FLOAT))          AS avg_trade_count,
        STDEV(CAST(market_trade_count AS FLOAT))        AS stdev_trade_count,
        AVG(CAST(ABS(market_intraday) AS FLOAT))        AS avg_price_var,
        STDEV(CAST(ABS(market_intraday) AS FLOAT))      AS stdev_price_var
    INTO #hist_stats
    FROM dbo.tb_symbol_stats
    WHERE process_date >= DATEADD(DAY, -30, @log_process_date)
      AND process_date <  @log_process_date
    GROUP BY symbol;


    -- ----------------------------------------------------------------
    -- Insert: tb_symbol_stats
    -- Driver: tb_quote (1 linha por ativo por dia de pregao)
    -- ----------------------------------------------------------------
    INSERT INTO dbo.tb_symbol_stats (
        process_date,
        symbol,
        market_open_price,
        market_close_price,
        market_avg_price,
        market_min_price,
        market_max_price,
        market_trade_count,
        market_intraday,
        market_interday,
        market_volume,
        market_qty,
        broker_trade_value_open,
        broker_trade_value_close,
        broker_trade_value_avg,
        broker_trade_value_min,
        broker_trade_value_max,
        broker_trade_count,
        broker_volume,
        broker_qty,
        broker_avg_quantity,
        distinct_client_count,
        distinct_broker_count,
        peak_volume_window,
        avg_trades_per_minute,
        avg_ticket,
        relevant_facts_count,
        broker_market_share_pct,
        is_volume_atypical,
        is_trade_count_atypical,
        is_price_var_atypical,
        created_at
    )
    SELECT
        CAST(q.symbol_timestamp AS DATE)                                    AS process_date,
        q.symbol,

        q.open_price                                                        AS market_open_price,
        q.close_price                                                       AS market_close_price,
        q.avg_price                                                         AS market_avg_price,
        q.min_price                                                         AS market_min_price,
        q.max_price                                                         AS market_max_price,
        q.trade_count                                                       AS market_trade_count,

        ISNULL(
            (q.close_price / NULLIF(q.open_price, 0)) - 1
        , 0)                                                                AS market_intraday,

        ISNULL(
            (q.open_price / NULLIF(q.yesterday_close_price, 0)) - 1
        , 0)                                                                AS market_interday,

        q.financial_volume                                                  AS market_volume,
        mq.market_qty,

        toc.broker_trade_value_open,
        toc.broker_trade_value_close,
        ta.broker_trade_value_avg,
        ta.broker_trade_value_min,
        ta.broker_trade_value_max,
        ISNULL(ta.broker_trade_count, 0)                                    AS broker_trade_count,
        ISNULL(ta.broker_volume, 0)                                         AS broker_volume,
        ISNULL(ta.broker_qty, 0)                                            AS broker_qty,
        ta.broker_avg_quantity,

        cs.distinct_client_count,
        bs.distinct_broker_count,
        hmv.peak_volume_window,

        ISNULL(
            CAST(q.trade_count AS DECIMAL(18,4))
            / NULLIF(CAST(sd.session_minutes AS DECIMAL(18,4)), 0)
        , 0)                                                                AS avg_trades_per_minute,

        ISNULL(q.financial_volume / NULLIF(q.trade_count, 0), 0)           AS avg_ticket,

        ISNULL(f.relevant_facts_count, 0)                                   AS relevant_facts_count,

        ISNULL(
            bq.broker_qty / NULLIF(mq.market_qty, 0) * 100
        , 0)                                                                AS broker_market_share_pct,

        -- is_volume_atypical: Z-score > 2.0 nos ultimos 30 dias
        CASE
            WHEN hs.stdev_volume > 0
             AND (CAST(q.financial_volume AS FLOAT) - hs.avg_volume) / hs.stdev_volume > 2.0
            THEN 1 ELSE 0
        END                                                                 AS is_volume_atypical,

        CASE
            WHEN hs.stdev_trade_count > 0
             AND (CAST(q.trade_count AS FLOAT) - hs.avg_trade_count) / hs.stdev_trade_count > 2.0
            THEN 1 ELSE 0
        END                                                                 AS is_trade_count_atypical,

        CASE
            WHEN hs.stdev_price_var > 0
             AND (ABS(CAST(ISNULL((q.close_price / NULLIF(q.open_price, 0)) - 1, 0) AS FLOAT)) - hs.avg_price_var) / hs.stdev_price_var > 2.0
            THEN 1 ELSE 0
        END                                                                 AS is_price_var_atypical,

        GETDATE()                                                           AS created_at

    FROM dbo.tb_quote q

    LEFT JOIN #trade_agg ta
        ON  ta.symbol       = q.symbol
        AND ta.process_date = CAST(q.symbol_timestamp AS DATE)

    LEFT JOIN #trade_open_close toc
        ON  toc.symbol       = q.symbol
        AND toc.process_date = CAST(q.symbol_timestamp AS DATE)

    LEFT JOIN #relevant_facts f
        ON  f.symbol = q.symbol

    LEFT JOIN #broker_qty bq
        ON  bq.symbol       = q.symbol
        AND bq.process_date = CAST(q.symbol_timestamp AS DATE)

    LEFT JOIN #market_qty mq
        ON  mq.symbol       = q.symbol
        AND mq.process_date = CAST(q.symbol_timestamp AS DATE)

    LEFT JOIN #client_summary cs
        ON  cs.symbol       = q.symbol
        AND cs.process_date = CAST(q.symbol_timestamp AS DATE)

    LEFT JOIN #broker_summary bs
        ON  bs.symbol       = q.symbol
        AND bs.process_date = CAST(q.symbol_timestamp AS DATE)

    LEFT JOIN #peak_volume_window hmv
        ON  hmv.symbol       = q.symbol
        AND hmv.process_date = CAST(q.symbol_timestamp AS DATE)

    LEFT JOIN #session_duration sd
        ON  sd.symbol       = q.symbol
        AND sd.process_date = CAST(q.symbol_timestamp AS DATE)

    LEFT JOIN #hist_stats hs
        ON  hs.symbol = q.symbol

    WHERE CAST(q.symbol_timestamp AS DATE) = @log_process_date;


    -- ----------------------------------------------------------------
    -- Insert: tb_symbol_stats_top_clients
    -- Top 5 clientes por volume financeiro por simbolo
    ---- ----------------------------------------------------------------
    INSERT INTO dbo.tb_symbol_stats_top_clients (
        process_date, symbol, rank_pos, account,
        client_volume, client_qty, client_trade_count, created_at
    )
    SELECT process_date, symbol, rank_pos, account,
           client_volume, client_qty, client_trade_count, GETDATE()
    FROM (
        SELECT
            process_date, symbol, account,
            client_volume, client_qty, client_trade_count,
            ROW_NUMBER() OVER (PARTITION BY process_date, symbol
                               ORDER BY client_volume DESC)  AS rank_pos
        FROM #client_agg
    ) ranked
    WHERE rank_pos <= 5;


    -- ----------------------------------------------------------------
    -- Insert: tb_symbol_stats_top_brokers
    -- Top 5 corretoras por volume por simbolo
    -- ----------------------------------------------------------------
    INSERT INTO dbo.tb_symbol_stats_top_brokers (
        process_date, symbol, rank_pos, broker_id,
        broker_volume, broker_trade_count, created_at
    )
    SELECT process_date, symbol, rank_pos, broker_id,
           broker_volume, broker_trade_count, GETDATE()
    FROM (
        SELECT
            process_date, symbol, broker_id,
            broker_volume, broker_trade_count,
            ROW_NUMBER() OVER (PARTITION BY process_date, symbol
                               ORDER BY broker_volume DESC)  AS rank_pos
        FROM #broker_agg
    ) ranked
    WHERE rank_pos <= 5;


    -- ----------------------------------------------------------------
    -- Insert: tb_symbol_stats_time_windows
    -- Todas as janelas horarias com volume > 0
    -- ----------------------------------------------------------------
    INSERT INTO dbo.tb_symbol_stats_time_windows (
        process_date, symbol, time_window,
        window_volume, window_trade_count, created_at
    )
    SELECT process_date, symbol, time_window,
           window_volume, window_trade_count, GETDATE()
    FROM #time_windows_agg;


    -- ----------------------------------------------------------------
    -- Insert: tb_symbol_stats_price_chart
    -- OHLC de 5 minutos para todos os ativos do dia
    -- ----------------------------------------------------------------
    INSERT INTO dbo.tb_symbol_stats_price_chart (
        process_date, symbol, interval_start,
        open_price, high_price, low_price, close_price,
        volume, trade_count, created_at
    )
    SELECT process_date, symbol, interval_start,
           open_price, high_price, low_price, close_price,
           volume, trade_count, GETDATE()
    FROM #price_chart;

 ----------------------------------------------------------------
 --SYMBOL STATS >>>>> FIM
 ----------------------------------------------------------------

    UPDATE log_ms
          SET dt_end               = GETDATE()
            , duration             = CAST(GETDATE() - dt_begin AS TIME)
            , status_description   = 'Completed'
      WHERE id_log = @LogID;

END TRY
BEGIN CATCH

    DECLARE @ERROR_MSG VARCHAR(1000) = ERROR_MESSAGE();

    UPDATE log_ms
          SET dt_end               = GETDATE()
            , duration             = CAST(GETDATE() - dt_begin AS TIME)
            , status_description   = 'Error: ' + ERROR_MESSAGE()
      WHERE id_log = @LogID;

    RAISERROR(@ERROR_MSG, 16, 1);

END CATCH;
