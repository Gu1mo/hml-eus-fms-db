CREATE procedure [dbo].[usp_alert_layering]
AS
------------------------------------------------------

/*

Descrição de alterações
Dia:23/07/2024 Author: Guimo
Inclusão do tratamento de log, para quando rodar novamente o mesmo dia apague das tabelas destino e insira novamente.
Dessa forma evidenciando o reprocessamento pela tabela de log.
Dia:27/07/2024 Author: Guimo
- Alteração da processo de log retirando a condição de completed para reprocessar
Dia:24/09/2024 Author: Guimo
-Inclusão das informações da tabela tb_trade na tabela de tb_order_layer_cycle_hist. Colunas adicionadas trade_time,brokcer_buy,broker_sell,direct e aggressor. Essas colunas só terão resultado quando forem referentes a trade. Exec_typpe = F.
Dia: 13/05/2025 - Guimo 
Inclusão do insert das ocorrencias 

Dia: 20/06/2025 - Guimo 
-- Inclusão da flag de recorrencia no alerta
-- Inclusão da flag de negócio direto (cross)
-- Mudança na lógica do alerta (refizemos baseado no layering da b3)
-- Considerando intervalo de negócios do arquivo de benchmark da bsm

Dia: 26/06/2025 - Guimo Gobbo
INclusaõ da coluna describe

29/08/2025 - Guimo
Alteração no codigo buscando melhoria de performance

30/09/2025 - Edu
Retirada dos indexs das tabelas temporarias

15/10/2025 - Guimo e Gobbo
Alteração na lógica para identificar quando o cancelamento ocorre antes do trade.

19/03/2026 - Guimo (solicitado por gobbo)
Trocar o nome da abertura de ocorrencia de FIRA para Admin.


17/06/2026 - Fix: Removido COMMIT/ROLLBACK pois a SP nao abre transacao propria.
              O driver ODBC gerencia a transacao externa; COMMIT aqui causava erro 266 (@@TRANCOUNT 1->0).
*/	
									
DECLARE @LogID INT;
DECLARE @log_process_date DATE = (SELECT max(process_date) FROM tb_order);

BEGIN TRY
    INSERT INTO log_ms (process, dt_exec, dt_begin,status_description,process_date)
    VALUES ('Layering', GETDATE(), GETDATE(), 'Started',@log_process_date);
    SET @LogID = SCOPE_IDENTITY();
	
	IF (SELECT COUNT(1) FROM log_ms WHERE process = 'Layering' AND process_date = @log_process_date) > 0
	BEGIN
	
		PRINT 'reprocessing...'

		DELETE FROM tb_order_buy_layer_hist		WHERE process_date = @log_process_date
		DELETE FROM tb_order_sell_layer_hist	WHERE process_date = @log_process_date
		DELETE FROM tb_order_layer_cycle_hist	WHERE process_date = @log_process_date
		DELETE FROM tb_order_layer_hist			WHERE process_date = @log_process_date
		DELETE FROM tb_account_layer_hist		WHERE process_date = @log_process_date
		DELETE FROM issues					    WHERE alert_name = 'Layering' and date = @log_process_date

	END
	ELSE
	BEGIN
		PRINT 'processing...'
	END	
------------------------------------------------------------------------------------------------------------------------------
/* LAYERING >>>>> INÍCIO */
------------------------------------------------------------------------------------------------------------------------------
 
	DROP TABLE IF EXISTS #cursor_data; 
	DECLARE @passo_minutos int = 5;

	WITH limites AS (
		SELECT process_date,
			   MIN(cast(order_timestamp as time(3))) AS min_hora,
			   MAX(cast(order_timestamp as time(3))) AS max_hora
		FROM tb_order
		GROUP BY process_date
	),
	-- base_inicio = início da HORA (HH:00:00.000) do menor horário do dia
	bounds AS (
		SELECT  process_date,
				CAST(DATEADD(HOUR, DATEPART(HOUR, min_hora), '00:00:00.000') AS time(3)) AS base_inicio,
				max_hora
		FROM limites
	),
	rec AS (
		SELECT process_date, inicio = base_inicio, max_hora
		FROM bounds
		UNION ALL
		SELECT r.process_date,
			   DATEADD(MINUTE, @passo_minutos, r.inicio),
			   r.max_hora
		FROM rec r
		JOIN bounds b ON b.process_date = r.process_date
		WHERE DATEADD(MINUTE, @passo_minutos, r.inicio) <= b.max_hora
	)
	SELECT  process_date,
			inicio                                  AS hora_inicio,
			DATEADD(MINUTE, @passo_minutos, inicio) AS hora_fim,
			ROW_NUMBER() over(order by inicio) id_bloco
	INTO #cursor_data
	FROM rec
	ORDER BY process_date, inicio
	OPTION (MAXRECURSION 32767);
	
 /*Informações de Benchmark*/
 DROP TABLE IF EXISTS #benchmark;
		SELECT symbol,
				DATEPART(HOUR, menor_media_intervalo_negs) * 3600000 +    -- Horas em milissegundos (1 hora = 3600 seg * 1000 ms/seg)
				DATEPART(MINUTE, menor_media_intervalo_negs) * 60000 +    -- Minutos em milissegundos (1 min = 60 seg * 1000 ms/seg)
				DATEPART(SECOND, menor_media_intervalo_negs) * 1000 +    -- Segundos em milissegundos (1 seg = 1000 ms/seg)
				DATEPART(MILLISECOND, menor_media_intervalo_negs) AS intervalo_neg_ms
		  INTO #benchmark
		  FROM tb_benchmark; 
		
				 
 /*Camada Verdadeira*/ 
 DROP TABLE IF EXISTS #camada_verdadeira;  
		SELECT A.order_key 
			 , A.process_date
			 , A.order_id			 
			 , A.account
			 , A.symbol
			 , A.exec_type
			 , A.ord_status
			 , A.secondary_order_id
			 , A.order_timestamp
			 , A.msg_type
			 , A.party_id
			 , A.book_timestamp
			 , A.book_spread
			 , A.order_spread
			 , A.trade_id
			 , isnull(A.price,A.last_px) price
			 , case when A.exec_type in('0','4','5') then A.quantity when A.exec_type = 'F' then A.lastqty end quantity
			 , CASE WHEN A.side = 1 then 'C' else 'V'  end side
			 , dateadd(MILLISECOND,- intervalo_neg_ms ,cast( A.order_timestamp as time(3))) AS min_hora
			 , cast(A.order_timestamp as time(3)) hora
			 , dateadd(MILLISECOND, intervalo_neg_ms ,cast( A.order_timestamp as time(3))) AS max_hora
			 , A.exec_type+A.ord_status AS type_status
			 , C.id_bloco 
		  INTO #camada_verdadeira
		  FROM tb_order A
		  JOIN #benchmark B
			ON A.symbol = b.symbol
	 LEFT JOIN #cursor_data C
			ON  C.process_date = A.process_date
			AND CAST(A.order_timestamp AS time(3)) between C.hora_inicio and C.hora_fim	
		 WHERE A.source_id = 1
		   AND A.exec_type = 'F' ;

 DROP TABLE IF EXISTS #tb_entrypoint;
	    SELECT A.process_date
			 , A.order_id			 
			 , A.account
			 , A.symbol
			 , A.exec_type
			 , A.ord_status
			 , isnull(A.price,A.last_px) price
			 , case when A.exec_type in('0','4','5') then A.quantity when A.exec_type = 'F' then A.lastqty end quantity
			 , CASE WHEN A.side = 1 then 'C' else 'V'  end side
			 , cast(A.order_timestamp as time(3)) hora
			 , A.secondary_order_id
			 , A.order_key
			 , A.order_timestamp
			 , A.msg_type
			 , A.party_id
			 , A.book_timestamp
			 , A.book_spread
			 , A.order_spread
			 , A.trade_id
			 , A.exec_type+A.ord_status AS type_status
			 , c.id_bloco
			 , case when A.exec_type+A.ord_status in ('F2','44') then 1 else 0 end as flag_trade_cancelada
			 , case when A.exec_type+A.ord_status in ('00','55') then 1 else 0 end as flag_insercao_sub
		  INTO #tb_entrypoint
		  FROM tb_order A 
	 LEFT JOIN #cursor_data C
			ON  C.process_date = A.process_date
			AND CAST(A.order_timestamp AS time(3)) between C.hora_inicio and C.hora_fim;

		--CREATE NONCLUSTERED INDEX idx_tb_entrypoint_symbol_date_hora
		--ON #tb_entrypoint (symbol, process_date, hora)
		--INCLUDE (side);

 DROP TABLE IF EXISTS #hora_camada_verdadeira;
		SELECT 
	  DISTINCT hora
			 , min_hora
			 , max_hora 
			 , side 
			 , symbol 
			 , process_date
			 , id_bloco 
		  INTO #hora_camada_verdadeira 
		  FROM #camada_verdadeira;
	  
/*Junção da camada verdadeira com a falsa (verdadeira + falsa) */

DROP TABLE IF EXISTS #camada_falsa
	   SELECT A.symbol
			, min_hora
			, A.hora
			, max_hora 
			, A.process_date 
			, B.side			   AS side_oposto
			, B.price			   as price_oposto
			, B.hora			   AS hora_oposto
			, B.order_id		   AS order_id_oposto
			, B.account			   AS account_oposto
			, B.exec_type		   AS exec_type_oposto
			, B.ord_status		   AS ord_status_oposto
			, B.quantity		   AS quantity_oposto	
			, B.secondary_order_id AS  secondary_order_id_oposto
			, B.order_timestamp	   AS order_timestamp_oposto
			, B.book_timestamp	   AS book_timestamp_oposto
			, B.book_spread		   AS book_spread_oposto
			, B.order_spread	   AS order_spread_oposto
			, B.trade_id		   AS trade_id_oposto
			, b.type_status		   as type_status_oposto
			, a.id_bloco 
			, flag_trade_cancelada
			, flag_insercao_sub
		 INTO #camada_falsa
		 FROM #hora_camada_verdadeira A
		 JOIN #tb_entrypoint B
		   ON a.symbol = b.symbol
		  AND a.process_date = b.process_date
		  AND a.side <> b.side
		  AND B.hora between A.min_hora and a.max_hora
		  OPTION (RECOMPILE, MAXDOP 4);

			
/*
	Conta eventos por order_id_oposto para identificar quais orders 
	-- terão melhoria de preço verificada, distinguindo dois casos:
	--   1) Orders com apenas evento de criação (tratamento específico)
	--   2) Orders com eventos de substituição (tratamento diferenciado)
*/

DROP TABLE IF EXISTS #camada_falsa_resultado;
CREATE TABLE #camada_falsa_resultado (
    order_key               BIGINT,
    process_date            DATE,
    order_id                BIGINT,
    account                 VARCHAR(50),
    symbol                  VARCHAR(50),
    price                   DECIMAL(18,6),
    exec_type               CHAR(1),
    ord_status              CHAR(1),
    quantity                DECIMAL(18,6),
    side                    CHAR(1),
    min_hora                TIME(3),
    hora                    TIME(3),
    max_hora                TIME(3),
    secondary_order_id      BIGINT,
    order_timestamp         DATETIME2(3),
    msg_type                CHAR(1),
    party_id                VARCHAR(50),
    book_timestamp          DATETIME2(3),
    book_spread             DECIMAL(18,6),
    order_spread            DECIMAL(18,6),
    trade_id                BIGINT,
    side_oposto             CHAR(1),
    price_oposto            DECIMAL(18,6),
    hora_oposto             TIME(3),
    order_id_oposto         BIGINT,
    account_oposto          VARCHAR(50),
    exec_type_oposto        CHAR(1),
    ord_status_oposto       CHAR(1),
    quantity_oposto         DECIMAL(18,6),
    secondary_order_id_oposto BIGINT,
    order_key_oposto        BIGINT,
    order_timestamp_oposto  DATETIME2(3),
    msg_type_oposto         CHAR(1),
    party_id_oposto         VARCHAR(50),
    book_timestamp_oposto   DATETIME2(3),
    book_spread_oposto      DECIMAL(18,6),
    order_spread_oposto     DECIMAL(18,6),
    trade_id_oposto         BIGINT,
    type_status_oposto      VARCHAR(10)
);


----------------------------------------------------
--tableas
-------------------------------------------------------
  drop table if exists #camada_falsa_consolidada; 
  SELECT  top 0 A.order_key				AS order_key,			
			A.process_date				AS process_date,
			A.order_id					AS order_id,
			A.account					AS account,
			A.symbol					AS symbol,
			A.price						AS price,
			A.exec_type					AS exec_type,
			A.ord_status				AS ord_status,
			A.quantity					AS quantity,
			A.side						AS side,
			A.min_hora					AS min_hora,
			A.hora						AS hora,
			A.max_hora					AS max_hora,
			A.secondary_order_id		AS secondary_order_id,
			A.order_timestamp			AS order_timestamp,
			A.msg_type					AS msg_type,
			A.party_id					AS party_id,
			A.book_timestamp			AS book_timestamp,
			A.book_spread				AS book_spread,
			A.order_spread				AS order_spread,
			A.trade_id					AS trade_id,
			B.side_oposto,
			B.price_oposto,
			B.hora_oposto,
			B.order_id_oposto,
			B.account_oposto,
			B.exec_type_oposto,
			B.ord_status_oposto,
			B.quantity_oposto,	
			B.secondary_order_id_oposto,
			B.order_timestamp_oposto,
			B.book_timestamp_oposto,
			B.book_spread_oposto,
			B.order_spread_oposto,
			B.trade_id_oposto,
			B.type_status_oposto,
			b.flag_trade_cancelada,
			b.flag_insercao_sub,
			case when b.hora_oposto < a.hora then 1 else 0 end flag_hora_oposto_menor_hora,
			a.id_bloco
		INTO #camada_falsa_consolidada
		FROM #camada_verdadeira A
		JOIN #camada_falsa B
		  ON a.process_date = b.process_date
		 AND a.symbol = b.symbol
		 AND a.side <> b.side_oposto 
		 AND a.hora = b.hora

	--CREATE NONCLUSTERED INDEX IDX02
	--ON [dbo].[#camada_falsa_consolidada] ([exec_type_oposto])
	--INCLUDE ([hora],[hora_oposto])
	
	--CREATE NONCLUSTERED INDEX IDX01
	--ON [dbo].[#camada_falsa_consolidada] ([type_status_oposto])
	--INCLUDE ([order_key],[order_id_oposto],[exec_type_oposto],[ord_status_oposto])
	
	--CREATE NONCLUSTERED INDEX idx_camada_falsa_join_filter
	--ON #camada_falsa_consolidada (order_key, order_id_oposto)
	--INCLUDE (hora_oposto, hora, type_status_oposto);

	--CREATE CLUSTERED INDEX CIX_camada_verdadeira
	--ON #camada_verdadeira (process_date, symbol, id_bloco, hora);

	--CREATE NONCLUSTERED INDEX IX_camada_verdadeira_side
	--ON #camada_verdadeira (process_date, symbol, hora, id_bloco)
	--INCLUDE (side);

	--CREATE CLUSTERED INDEX CIX_camada_falsa
	--ON #camada_falsa (process_date, symbol, id_bloco, hora);

	--CREATE NONCLUSTERED INDEX IX_camada_falsa_side
	--ON #camada_falsa (process_date, symbol, hora, id_bloco, side_oposto);
-------------------------------------------------------
-- Declaração das variáveis
-------------------------------------------------------
DECLARE 
	@id_bloco int;

-------------------------------------------------------
-- Criação do cursor
-------------------------------------------------------
DECLARE camada_cursor CURSOR FOR
    SELECT 
  DISTINCT id_bloco          
      FROM #cursor_data    
  ORDER BY id_bloco

-------------------------------------------------------
-- Execução do cursor
-------------------------------------------------------
OPEN camada_cursor;

FETCH NEXT FROM camada_cursor INTO @id_bloco;

DECLARE @contador INT = 0,
        @total INT;

-- pega total de linhas a processar
SELECT @total = COUNT(*) FROM #cursor_data;


WHILE @@FETCH_STATUS = 0
BEGIN
    SET @contador = @contador + 1;
	--------------------------------------------------------------------------
	
	RAISERROR('Processadas %d de %d linhas', 0, 1, @contador, @total) WITH NOWAIT;

	TRUNCATE TABLE #camada_falsa_consolidada;
	INSERT INTO #camada_falsa_consolidada
    SELECT  A.order_key					AS order_key,			
			A.process_date				AS process_date,
			A.order_id					AS order_id,
			A.account					AS account,
			A.symbol					AS symbol,
			A.price						AS price,
			A.exec_type					AS exec_type,
			A.ord_status				AS ord_status,
			A.quantity					AS quantity,
			A.side						AS side,
			A.min_hora					AS min_hora,
			A.hora						AS hora,
			A.max_hora					AS max_hora,
			A.secondary_order_id		AS secondary_order_id,
			A.order_timestamp			AS order_timestamp,
			A.msg_type					AS msg_type,
			A.party_id					AS party_id,
			A.book_timestamp			AS book_timestamp,
			A.book_spread				AS book_spread,
			A.order_spread				AS order_spread,
			A.trade_id					AS trade_id,
			B.side_oposto,
			B.price_oposto,
			B.hora_oposto,
			B.order_id_oposto,
			B.account_oposto,
			B.exec_type_oposto,
			B.ord_status_oposto,
			B.quantity_oposto,	
			B.secondary_order_id_oposto,
			B.order_timestamp_oposto,
			B.book_timestamp_oposto,
			B.book_spread_oposto,
			B.order_spread_oposto,
			B.trade_id_oposto,
			B.type_status_oposto,
			case when type_status_oposto in ('F2','44') then 1 else 0 end as flag_trade_cancelada,
			case when type_status_oposto in ('00','55') then 1 else 0 end as flag_insercao_sub,
			case when b.hora_oposto < a.hora then 1 else 0 end flag_hora_oposto_menor_hora,
			a.id_bloco
		FROM #camada_verdadeira A
		JOIN #camada_falsa B
		  ON a.process_date = b.process_date
		 AND a.symbol = b.symbol
		 AND a.side <> b.side_oposto 
		 AND a.hora = b.hora
		 AND a.id_bloco = b.id_bloco
		 and a.id_bloco = @id_bloco

   DROP TABLE IF EXISTS #qtd_status
		  SELECT order_key
			   , order_id_oposto 
			   , id_bloco 
			   , ISNULL(SUM(CASE WHEN exec_type_oposto + ord_status_oposto = '00' THEN 1 END),0) qtd_nova
			   , ISNULL(SUM(CASE WHEN exec_type_oposto + ord_status_oposto = '55' THEN 1 END),0) qtd_sub
			INTO #qtd_status
			FROM #camada_falsa_consolidada
		   WHERE flag_trade_cancelada = 0
		GROUP BY  order_key 
			   , order_id_oposto
			   , id_bloco ;

	DROP TABLE IF EXISTS #tipo_verificacao
		SELECT order_key 
			 , order_id_oposto 
			 , id_bloco 
			 , CASE WHEN SUM(qtd_nova  + qtd_sub ) =  1 
					THEN 1 
					ELSE 2 END AS flag_tipo_verificacao

		  INTO #tipo_verificacao
		  FROM #qtd_status
	  GROUP BY order_key
			 , order_id_oposto
			 , id_bloco 

/*
 * Classifica eventos (criação/substituição) via flags 1/2 para verificação pré-trade:
 * 1: Análise na oferta anterior (ciclo único) 
 * 2: Análise de evolução de preços no próprio order_id
 * Objetivo: Identificar melhorias de preço antes da execução
 */

	--CREATE NONCLUSTERED INDEX idx_tipo_verificacao_join
	--ON #tipo_verificacao (order_key, order_id_oposto);

	DROP TABLE IF EXISTS #flag_tipo_verificacao_base
		   select A.order_key 
				, A.process_date
				, A.order_id
				, A.account
				, A.symbol
				, A.price
				, A.exec_type
				, A.ord_status
				, A.quantity
				, A.side
				, A.min_hora
				, A.hora
				, A.max_hora
				, A.side_oposto
				, A.price_oposto
				, A.hora_oposto
				, A.order_id_oposto
				, A.account_oposto
				, A.exec_type_oposto
				, A.ord_status_oposto
				, A.quantity_oposto	 
				, b.flag_tipo_verificacao
				, a.id_bloco
			 INTO #flag_tipo_verificacao_base
			 FROM #camada_falsa_consolidada A		
			 JOIN #tipo_verificacao B
			   ON a.order_key = b.order_key
			  AND a.order_id_oposto = b.order_id_oposto		
			WHERE  a.hora_oposto < a.hora 
			  AND a.type_status_oposto in ('00','55'); 


		--CREATE NONCLUSTERED INDEX idx_flag_verificacao_base
		--ON #flag_tipo_verificacao_base (process_date, symbol, min_hora)
		--INCLUDE (hora_oposto);

------------------------------------------------------------------
drop table if exists #temp_aux_flag_melhora_preco;
SELECT 
    A.order_key,
    A.symbol,
    A.process_date,
    A.order_id_oposto,
    A.exec_type_oposto,
    A.flag_tipo_verificacao,
    A.hora_oposto,
    A.price_oposto,
    A.side_oposto,
    B.hora,
    B.order_id,
    B.exec_type,
    B.ord_status,
    B.price AS price_base,
	id_bloco
	into #temp_aux_flag_melhora_preco
FROM #flag_tipo_verificacao_base A
CROSS APPLY (
    SELECT TOP 1 
        B.hora,
        B.order_id,
        B.exec_type,
        B.ord_status,
        B.price
    FROM #tb_entrypoint B
    WHERE B.process_date = A.process_date
      AND B.symbol = A.symbol
      AND B.hora >= A.min_hora
      AND B.hora < A.hora_oposto
      AND B.type_status IN ('00','55')

    ORDER BY B.hora DESC
) B

WHERE A.flag_tipo_verificacao = 1
OPTION (MAXDOP 4);


  DROP TABLE IF EXISTS #flag_melhora_preco_sub_nova;
		  SELECT   order_key
			    , process_date
				, symbol
				, order_id
				, order_id_oposto
				, hora_oposto
				, flag_tipo_verificacao
				, ISNULL(x.price_oposto - x.price_base,0) AS diff_price_ant
				, CASE 
					WHEN side_oposto = 'C' and ISNULL(x.price_oposto - x.price_base,0) < 0 THEN 'N'
					WHEN side_oposto = 'C' and ISNULL(x.price_oposto - x.price_base,0) = 0 THEN 'M'
					WHEN side_oposto = 'V' and ISNULL(x.price_oposto - x.price_base,0) > 0 THEN 'N'
					WHEN side_oposto = 'V' and ISNULL(x.price_oposto - x.price_base,0) = 0 THEN 'M'
					ELSE 'S'
				END flag_melhora_preco
		    INTO #flag_melhora_preco_sub_nova
		  FROM #temp_aux_flag_melhora_preco X

				UNION ALL
	
		   SELECT order_key
			    , process_date
				, symbol
				, order_id
				, order_id_oposto
				, hora_oposto
				, flag_tipo_verificacao
				, ISNULL(a.price_oposto - LAG(a.price_oposto) OVER(PARTITION BY a.order_Key ORDER BY a.hora_oposto),0) AS diff_price_ant
				, CASE 
					WHEN side_oposto = 'C' and ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id order by hora_oposto),0) < 0 THEN 'N'
					WHEN side_oposto = 'C' and ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id order by hora_oposto),0) = 0 THEN 'M'
					WHEN side_oposto = 'V' and ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id order by hora_oposto),0) > 0 THEN 'N'
					WHEN side_oposto = 'V' and ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id order by hora_oposto),0) = 0 THEN 'M'
					ELSE 'S'
				END flag_melhora_preco
			 FROM #flag_tipo_verificacao_base A
		    WHERE flag_tipo_verificacao = 2 


/**
 * Regra de exclusão de order_id no lado falso:
 * 
 * Remove completamente um order_id da camada falsa caso seu 
 * order_id oposto correspondente possua PELO MENOS UMA ocorrência 
 * de flag_melhora_preco = 'N'.
 * 
 * Lógica:
 *   - A existência de qualquer registro com 'N' na flag_melhora_preco 
 *     do lado oposto invalida todas as entradas do order_id no lado falso
 *   - Critério aplicado ANTES da análise de melhoria de preço
 *   - Remove o order_id por completo (todas suas linhas/eventos)
 * 
 * Propósito: 
 *   Garantir integridade na verificação de melhoria de preço
 *   eliminando orders com indicadores negativos prévios no lado oposto.
 */	

DELETE 
  FROM #camada_falsa_consolidada
 WHERE exists (SELECT 1 
				 FROM(     SELECT 
						 DISTINCT order_key 
								, symbol
								, process_date
								, order_id 
								, order_id_oposto 
							 FROM #flag_melhora_preco_sub_nova
							WHERE flag_melhora_preco = 'N'
					 ) x
				 WHERE #camada_falsa_consolidada.order_key	     = X.order_key
				   AND #camada_falsa_consolidada.process_date    = x.process_date
				   AND #camada_falsa_consolidada.symbol		     = x.symbol
				   AND #camada_falsa_consolidada.order_id_oposto = x.order_id_oposto
			   )   AND  hora_oposto < hora;

/** 
 * Exclui trades da camada falsa 
 * com timestamp anterior ao trade real 
 */
DELETE 
  FROM #camada_falsa_consolidada 
 WHERE EXISTS (SELECT 1 
				 FROM (
						SELECT 
					  DISTINCT order_key
							 , order_id
							 , order_id_oposto  
						  FROM #camada_falsa_consolidada 
						 WHERE hora_oposto <= hora
						   AND exec_type_oposto = 'F'
					  ) x 
			    WHERE #camada_falsa_consolidada.order_key = x.order_key
				  AND #camada_falsa_consolidada.order_id = x.order_id
				  AND #camada_falsa_consolidada.order_id_oposto = x.order_id_oposto
			  )  ;


/** Remove pre-trade (cancel/trade/8) da falsa */
--DELETE 
--  FROM #camada_falsa_consolidada 
-- WHERE flag_hora_oposto_menor_hora = 1 -- hora_oposto < hora 
--   AND exec_type_oposto in ('4','8');



/** 
 * Remove ofertas sem histórico relevante: 
 * apenas 1 evento na camada falsa 
 */
DELETE 
  FROM #camada_falsa_consolidada
 WHERE EXISTS ( SELECT 1 
				  FROM (
					   SELECT order_key
							, symbol
							, process_date 
						 FROM #camada_falsa_consolidada
					    WHERE flag_hora_oposto_menor_hora =1 -- hora_oposto < hora
					 GROUP BY order_key
							, symbol
							, process_date
					   HAVING count(1) = 1
					   )x
				  WHERE #camada_falsa_consolidada.order_key    = x.order_key
					AND #camada_falsa_consolidada.symbol	   = x.symbol
					AND #camada_falsa_consolidada.process_date = x.process_date
			   );
			   

/** 
 * Exclui ofertas (camada falsa) criadas 
 * após trade da camada verdadeira 
 */
DELETE 
  FROM #camada_falsa_consolidada 
 WHERE EXISTS (SELECT 1 
				 FROM (
						SELECT 
					  DISTINCT  order_key
							 , order_id 
							 , order_id_oposto
						  FROM #camada_falsa_consolidada 
						 WHERE hora_oposto >= hora
						   AND exec_type_oposto = '0'
					  ) x 
			  WHERE #camada_falsa_consolidada.order_key		  = x.order_key
			    AND #camada_falsa_consolidada.order_id		  = x.order_id
			    AND #camada_falsa_consolidada.order_id_oposto = x.order_id_oposto
			  );

/** 
 * Deleta contas (camada falsa) cujos trades ocorrem 
 * durante o período de negociação da camada verdadeira 
 */
DELETE 
  FROM #camada_falsa_consolidada 
 WHERE EXISTS ( SELECT 1 
				  FROM (
					   SELECT 
					 DISTINCT order_key
							, order_id 
							, order_id_oposto 
							, account
						 FROM #camada_falsa_consolidada 
						WHERE flag_hora_oposto_menor_hora = 1 --hora_oposto >= hora
						  AND exec_type_oposto = 'F'
					   ) x 
				   WHERE #camada_falsa_consolidada.order_key	   = x.order_key
				     AND #camada_falsa_consolidada.order_id		   = x.order_id
					 AND #camada_falsa_consolidada.account		  = x.account
				);
		

/** 
 * [1] Identifica ofertas com cancelamentos/substituições pós-trade
 * [2] Remove da camada verdadeira as ofertas SEM esses eventos 
 */
DELETE
  FROM #camada_falsa_consolidada  
 WHERE NOT EXISTS ( SELECT 1 
                      FROM ( SELECT 
					       DISTINCT order_key
								  , process_date 
								  , symbol  
								  , order_id_oposto 
								  , exec_type_oposto
							   FROM #camada_falsa_consolidada
							  WHERE hora_oposto > hora
							    AND exec_type_oposto in ('4','5')
							) x
			        WHERE #camada_falsa_consolidada.order_key = x.order_key
					  AND #camada_falsa_consolidada.process_date = x.process_date
					  AND #camada_falsa_consolidada.symbol = x.symbol
					  AND #camada_falsa_consolidada.order_id_oposto = x.order_id_oposto	
				);
	
/** 
 * Deleta order_id_oposto com apenas 
 * uma linha/evento associado 
 */
DELETE 
  FROM #camada_falsa_consolidada
 WHERE EXISTS (SELECT 1 
				 FROM ( SELECT order_key 
						     , symbol 
							 , process_date
							 , order_id_oposto 
							 , count(1) qtd_rows 
						  FROM #camada_falsa_consolidada 
					  GROUP BY order_key 
					         , symbol 
							 , process_date
							 , order_id_oposto 
					    HAVING count(1) = 1
					  ) X
				  WHERE #camada_falsa_consolidada.order_key		  = x.order_key
					AND #camada_falsa_consolidada.process_date	  = x.process_date
					AND #camada_falsa_consolidada.symbol		  = x.symbol
					AND #camada_falsa_consolidada.order_id_oposto = x.order_id_oposto);	  

/** 
 * Verifica piora de preço e mantém APENAS 
 * as entidades que tiveram preço deteriorado 
 */
WITH OrderedOrders AS (

    SELECT 
        order_key,
		process_date,
        symbol,
        account,
        side,
        price,
		account_oposto ,
		order_id_oposto,
		side_oposto ,
        hora_oposto,
        exec_type_oposto,
        ord_status_oposto,
		price_oposto,
        LAG(price_oposto) OVER (
            PARTITION BY order_key , account_oposto, symbol 
            ORDER BY hora_oposto
        ) AS previous_price
    FROM #camada_falsa_consolidada

), piora as (

	SELECT 
		order_key,process_date,
		symbol,
		account,
		side,
		price,
		side_oposto,
		hora_oposto,
		order_id_oposto ,
		account_oposto,
		exec_type_oposto,
		ord_status_oposto,
		price_oposto,
		previous_price,
		CASE 
			WHEN side_oposto = 'C' AND (price_oposto - previous_price) <= 0 THEN 1
			WHEN side_oposto = 'C' AND (price_oposto - previous_price) >  0 THEN 0
			WHEN side_oposto = 'V' AND (price_oposto - previous_price) >= 0 THEN 1
			WHEN side_oposto = 'V' AND (price_oposto - previous_price) <  0 THEN 0
		
			ELSE 0 
		END AS flag_piora_preco
	FROM OrderedOrders

) , delete_quem_nao_piorou AS (

		SELECT order_key,
			   symbol,
			   process_date,
			   sum(flag_piora_preco) AS flag_piora_preco
		  FROM piora 
	  GROUP BY order_key,
			   symbol,
			   process_date
		HAVING SUM(flag_piora_preco) = 0

)

DELETE 
  FROM #camada_falsa_consolidada 
 WHERE EXISTS (SELECT 1 
				 FROM delete_quem_nao_piorou B
				WHERE #camada_falsa_consolidada.order_key = b.order_key
				  and #camada_falsa_consolidada.process_date = b.process_date
				  and #camada_falsa_consolidada.symbol = b.symbol) and exec_type_oposto = '5';


/** 
 * Verifica se o cliente operou no lado oposto 
 * durante o período de negociação.
 * 
 * Ação: Exclui o cliente caso a condição seja atendida.
 */

DELETE 
  FROM #camada_falsa_consolidada 
 WHERE EXISTS (SELECT 1 
				 FROM (	SELECT A.order_key 
							 , a.process_date 
							 , a.symbol 
							 , a.order_id 
							 , a.side
							 , a.min_hora , a.hora, a.max_hora
							 , a.account
							 , b.account account_oposto					
							 , b.hora hora_oposta
							 , b.side side_oposto
							 , b.order_id order_id_oposto
							 , b.price price_oposto
						  FROM #camada_falsa_consolidada A
						  JOIN #tb_entrypoint B 
							ON a.symbol = b.symbol
						   AND a.process_date = b.process_date
						   AND a.account = b.account
						   and a.id_bloco = b.id_bloco
						   AND b.exec_type = 'F'
						   AND b.side <> a.side
					   )x 
				WHERE #camada_falsa_consolidada.order_key = x.order_key
			      AND #camada_falsa_consolidada.symbol = x.symbol
			      AND #camada_falsa_consolidada.process_date = x.process_date
			   );
		  
/** 
 * Identifica ciclos que contêm PELO MENOS UMA oferta 
 * criada ou substituída ANTES do evento de trade 
 */
DELETE 
  FROM #camada_falsa_consolidada
 WHERE NOT EXISTS ( SELECT 1 
					  FROM (
							 SELECT 
						   DISTINCT order_key 
								  , symbol 
								  , process_date
							   FROM #camada_falsa_consolidada
							  WHERE hora_oposto < hora
							    AND exec_type_oposto IN ('0','5')
							) x
					   WHERE #camada_falsa_consolidada.order_key = x.order_key
						 AND #camada_falsa_consolidada.symbol = x.symbol
						 AND #camada_falsa_consolidada.process_date = x.process_date 
				     );

/*
* Verifica piora de preço pós trade
*/
DROP TABLE IF EXISTS #verificar_pos_trade;
    SELECT order_key 
		 , process_date 
		 , order_id 
		 , account
		 , symbol
		 , price
		 , side
		 , hora 
		 , hora_oposto 
		 , side_oposto 
		 , order_id_oposto
		 , exec_type_oposto 
		 , ord_status_oposto 
		 , type_status_oposto 
		 , price_oposto
		 , CASE WHEN hora_oposto < hora THEN 'Antes' WHEN hora_oposto > hora THEN 'Depois' ELSE 'Igual' END AS ordem_horas
	  INTO #verificar_pos_trade
	  FROM #camada_falsa_consolidada a
  ORDER BY order_key 
		 , book_timestamp_oposto

 DROP TABLE IF EXISTS #pega_ultima_antes;
		SELECT * 
			 , ROW_NUMBER() OVER(PARTITION BY order_key, order_id_oposto ORDER By hora_oposto DESC) rn
		  INTO #pega_ultima_antes
		  FROM #verificar_pos_trade
		 WHERE ordem_horas = 'Antes';

 DELETE FROM #pega_ultima_antes WHERE rn > 1;

 DROP TABLE IF EXISTS #verificar_piora_preco;
 SELECT order_key 
	  , process_date 
	  , order_id 
	  , account 
	  , symbol
	  , price
	  , side
	  , hora
	  , hora_oposto
	  , side_oposto
	  , order_id_oposto
	  , exec_type_oposto
	  , ord_status_oposto
	  , type_status_oposto
	  , price_oposto
	  , ordem_horas
 INTO #verificar_piora_preco
 FROM #pega_ultima_antes

 UNION ALL

 SELECT order_key 
	  , process_date 
	  , order_id 
	  , account 
	  , symbol
	  , price
	  , side
	  , hora
	  , hora_oposto
	  , side_oposto
	  , order_id_oposto
	  , exec_type_oposto
	  , ord_status_oposto
	  , type_status_oposto
	  , price_oposto
	  , ordem_horas 
  FROM #verificar_pos_trade 
 WHERE ordem_horas = 'Depois';

 DROP TABLE IF EXISTS #melhora_preco_pos_trade;
	SELECT * 
		 , LAG(price_oposto) over(partition by order_key,order_id_oposto order by hora_oposto) AS price_oposto_ant
		 , ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id_oposto ORDER BY hora_oposto),0) AS diff_price_ant
				, CASE 
					WHEN side_oposto = 'C' and ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id_oposto order by hora_oposto),0) < 0 THEN 'N'
					WHEN side_oposto = 'C' and ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id_oposto order by hora_oposto),0) = 0 THEN 'M'
					WHEN side_oposto = 'V' and ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id_oposto order by hora_oposto),0) > 0 THEN 'N'
					WHEN side_oposto = 'V' and ISNULL(price_oposto - LAG(price_oposto) OVER(PARTITION BY order_Key,order_id_oposto order by hora_oposto),0) = 0 THEN 'M'
					ELSE 'S'
				END flag_melhora_preco 
		 INTO #melhora_preco_pos_trade
		 FROM #verificar_piora_preco;

	    DELETE  
		  FROM #camada_falsa_consolidada 
		 WHERE EXISTS ( SELECT 1 
						  FROM #melhora_preco_pos_trade B
						 WHERE #camada_falsa_consolidada.order_key = b.order_key
						   AND #camada_falsa_consolidada.order_id_oposto = b.order_id_oposto
						   AND b.flag_melhora_preco in( 'S' , 'M') );				


/** 
 * Identifica ciclos que contêm PELO MENOS UMA oferta 
 * criada ou substituída ANTES do evento de trade 
 */
DELETE 
  FROM #camada_falsa_consolidada
 WHERE NOT EXISTS ( SELECT 1 
					  FROM (
							 SELECT 
						   DISTINCT order_key 
								  , symbol 
								  , process_date
							   FROM #camada_falsa_consolidada
							  WHERE flag_hora_oposto_menor_hora  =1 -- hora_oposto < hora hora_oposto < hora
							    AND exec_type_oposto IN ('0','5')
							) x
					   WHERE #camada_falsa_consolidada.order_key = x.order_key
						 AND #camada_falsa_consolidada.symbol = x.symbol
						 AND #camada_falsa_consolidada.process_date = x.process_date 
				     );

/** 
 * Deleta ciclos que possuem APENAS UM 
 * registro na camada falsa 
 */

DELETE 
  FROM #camada_falsa_consolidada
 WHERE exists( SELECT 1 
				 FROM (
						SELECT order_key 
							 , symbol 
							 , process_date 
						  FROM #camada_falsa_consolidada
						 WHERE hora_oposto < hora 
					  GROUP BY order_key , symbol , process_date 
						HAVING count(1) = 1
					  ) X
				  WHERE #camada_falsa_consolidada.order_key = x.order_key
					AND #camada_falsa_consolidada.symbol = x.symbol
					AND #camada_falsa_consolidada.process_date = x.process_date 
			 ); 

	
			 insert into #camada_falsa_resultado
			 select  order_key
				,process_date            
				,order_id                
				,account                 
				,symbol                  
				,price                   
				,exec_type               
				,ord_status              
				,quantity                
				,side                    
				,min_hora                
				,hora                    
				,max_hora                
				,secondary_order_id      
				,order_timestamp         
				,msg_type                
				,party_id                
				,book_timestamp          
				,book_spread             
				,order_spread            
				,trade_id                
				,side_oposto             
				,price_oposto            
				,hora_oposto             
				,order_id_oposto         
				,account_oposto          
				,exec_type_oposto        
				,ord_status_oposto       
				,quantity_oposto         
				,secondary_order_id_oposto 
				,null order_key_oposto        
				,order_timestamp_oposto  
				,null msg_type_oposto         
				,null party_id_oposto         
				,book_timestamp_oposto   
				,book_spread_oposto      
				,order_spread_oposto     
				,trade_id_oposto         
				,type_status_oposto      
			 From #camada_falsa_consolidada
	--------------------------------------------------------------------------------
    -- Aqui entra a lógica que você precisa para cada linha
    RAISERROR('Processadas %d de %d linhas', 0, 1, @contador, @total) WITH NOWAIT;

    FETCH NEXT FROM camada_cursor INTO @id_bloco;
END

CLOSE camada_cursor;
DEALLOCATE camada_cursor;



/** 
 * Verifica Recorrência
 */

DROP TABLE IF EXISTS #recorrencia;
	  DECLARE @process_date DATE = (SELECT max(process_date) FROM tb_entrypoint)
	   SELECT 
	 DISTINCT account
			, process_date 
		 INTO #recorrencia
		 FROM tb_account_layer_hist 
		WHERE process_date >= dateadd(day,-180, @process_date) 
		  AND process_date < @process_date;		
		  
/** 
 * Resultado preparação para os inserts nas tabelas
 */			

	 DROP TABLE IF EXISTS #tb_account;
			SELECT 
		  DISTINCT account 
			     , symbol
				 , process_date 
			 INTO #tb_account
			  FROM #camada_falsa_resultado A
			 WHERE NOT EXISTS (
								SELECT 1
								  FROM tb_account_layer_hist b
								 WHERE a.account = b.account
								   AND a.symbol = b.symbol
								   AND a.process_date = b.process_date
							   );

	 DROP TABLE IF EXISTS #tb_order;
		    SELECT 
		  DISTINCT A.order_key 
				 , A.order_id 
				 , A.secondary_order_id
				 , A.account
				 , A.order_timestamp
				 , A.msg_type
				 , A.party_id
				 , A.price
				 , A.quantity
				 , CASE WHEN A.side = 'C' THEN 1 ELSE 2 END AS side
				 , A.symbol
				 , A.exec_type
				 , A.ord_status
				 , A.process_date
				 , A.book_timestamp
				 , A.book_spread
				 , A.order_spread
				 , case when b.direct = 1 then 1 else 0 end flag_cross
				 , case when c.account is not null then 1 else 0 end flag_recurrence
			  INTO #tb_order
			  FROM  #camada_falsa_resultado A
			  JOIN tb_trade B
			    ON a.trade_id = b.trade_id
			   AND a.process_date = b.process_date
			   AND a.symbol = b.symbol
		 LEFT JOIN #recorrencia C
			    ON a.account = c.account
		  ORDER BY symbol 
			     , order_key
			     , order_id 

		DROP TABLE IF EXISTS #tb_trade_cycle;
			   SELECT
			 DISTINCT b.symbol
					, b.price
					, b.quantity
					, b.trade_time
					, b.broker_buy
					, b.broker_sell
					, b.direct
					, b.aggressor
					, b.trade_id
					, b.process_date 
			     INTO #tb_trade_cycle
			     FROM #camada_falsa_resultado A
			     JOIN tb_trade B
			       ON a.trade_id = b.trade_id
			      AND a.symbol   = b.symbol

	 DROP TABLE IF EXISTS #tb_cycle;

			SELECT
		  DISTINCT A.order_key 
				 , A.order_key								 AS related_order_key 
				 , A.order_id
				 , A.secondary_order_id						 AS secondary_order_id 
				 , A.account								 AS account
				 , A.order_timestamp						 AS order_timestamp
				 , A.msg_type								 AS  msg_type
				 , A.party_id								 AS  party_id
				 , case when a.side = 'C' then 1 else 2 end  AS side  
				 , A.price									 AS price
				 , A.quantity								 AS quantity
				 , A.symbol										 
				 , A.exec_type								 AS exec_type
				 , A.ord_status							     AS ord_status
				 , A.process_date									 
				 , DATEADD(HOUR, -3,A.book_timestamp) 		 AS book_timestamp 
				 , A.book_spread							 AS book_spread
				 , A.order_spread							 AS  order_spread
				 , A.trade_id								 AS  trade_id
				 , b.trade_time
				 , b.broker_buy
				 , b.broker_sell
				 , b.direct
				 , b.aggressor
			  INTO #tb_cycle
			  FROM #camada_falsa_resultado A
		 LEFT JOIN #tb_trade_cycle b 
				ON a.trade_id = b.trade_id 
			   AND a.symbol = b.symbol 
			   AND a.process_date = b.process_date

			 UNION

			SELECT A.order_key 
				 , A.order_key_oposto								 AS related_order_key 
				 , A.order_id_oposto order_id 
				 , A.secondary_order_id_oposto						 AS secondary_order_id 
				 , A.account_oposto									 AS account
				 , A.order_timestamp_oposto							 AS order_timestamp
				 , null 											 AS msg_type --A.msg_type_oposot	
				 , A.party_id_oposto								 AS party_id
				 , CASE WHEN a.side_oposto = 'C' THEN 1 ELSE 2 END   AS side  
				 , A.price_oposto									 AS price
				 , A.quantity_oposto								 AS quantity
				 , A.symbol										 
				 , A.exec_type_oposto								 AS exec_type
				 , A.ord_status_oposto							     AS ord_status
				 , A.process_date									 
				 , DATEADD(HOUR, -3,A.book_timestamp_oposto) 		 AS book_timestamp 
				 , A.book_spread_oposto								 AS book_spread
				 , A.order_spread_oposto							 AS order_spread
				 , A.trade_id_oposto								 AS trade_id
				 , b.trade_time
				 , b.broker_buy
				 , b.broker_sell
				 , b.direct
				 , b.aggressor
			  FROM #camada_falsa_resultado A --#tb_order_layering
		 LEFT JOIN #tb_trade_cycle b 
				ON a.trade_id_oposto = b.trade_id 
			   AND a.symbol = b.symbol 
			   AND a.process_date = b.process_date

		  ORDER BY DATEADD(HOUR, -3,A.book_timestamp);


	 DROP TABLE IF EXISTS #book_buy;
			SELECT A.order_key
				 , A.related_order_key AS related_order_key
				 , b.secondary_order_id
				 , DATEADD(HOUR,-3,b.buy_timestamp) AS buy_timestamp
				 , B.symbol
				 , B.position
				 , B.price
				 , B.quantity
				 , B.buy_broker
				 , B.process_date
			  INTO #book_buy
			  FROM #tb_cycle A 
			  JOIN tb_order_book_buy B
			    ON A.symbol			   = b.symbol
			   AND a.process_date	   = b.process_date
			   AND a.related_order_key = b.order_key
		   --WHERE B.order_key in (select distinct A.order_key from #camada_falsa) --WHERE order_key in (select distinct related_order_key from #tb_order_layering) 
		  ORDER BY 2 
				 , position;

	 DROP TABLE IF EXISTS #book_sell;
			SELECT A.order_key
				 , A.related_order_key AS related_order_key
				 , b.secondary_order_id
				 , DATEADD(HOUR,-3,b.sell_timestamp) AS sell_timestamp
				 , B.symbol
				 , B.position
				 , B.price
				 , B.quantity
				 , B.sell_broker
				 , B.process_date  
			  INTO #book_sell
			  FROM #tb_cycle A 
			  JOIN tb_order_book_sell B
			    ON A.symbol = b.symbol
			   AND a.process_date = b.process_date
			   AND a.related_order_key    = b.order_key
		     --WHERE B.order_key in (select distinct A.order_key_oposto from #camada_falsa) --WHERE order_key in (select distinct related_order_key from #tb_order_layering) 
		  ORDER BY 2 
				 , position;

/** 
 * Inserts Finais
 */	

	 INSERT INTO tb_account_layer_hist (account,symbol,process_date)
		  SELECT account
			   , symbol
			   , process_date 
		    FROM #tb_account;

	 INSERT INTO tb_order_layer_hist (order_key, order_id, secondary_order_id, account, order_timestamp, msg_type, party_id, price, side, symbol, exec_type, ord_status, process_date, book_timestamp, book_spread, order_spread,quantity,flag_cross,flag_recurrence)
		  SELECT order_key
			   , order_id
			   , secondary_order_id
			   , account
			   , order_timestamp
			   , msg_type
			   , party_id
			   , price
			   , side
			   , symbol
			   , exec_type
			   , ord_status
			   , process_date
			   , book_timestamp
			   , book_spread
			   , order_spread
			   , quantity
			   , flag_cross
			   , flag_recurrence
		    FROM #tb_order;	
	 
	 INSERT INTO tb_order_layer_cycle_hist (order_key,related_order_key, order_id, secondary_order_id, account, order_timestamp, msg_type, party_id, price, side, symbol, exec_type, ord_status, process_date, book_timestamp, book_spread, order_spread,quantity,trade_id,trade_time,broker_buy,broker_sell,direct,aggressor,describe)
		  SELECT order_key
			   , related_order_key
			   , order_id
			   , secondary_order_id
			   , account
			   , order_timestamp
			   , msg_type
			   , party_id
			   , price
			   , side
			   , symbol
			   , exec_type
			   , ord_status
			   , process_date
			   , book_timestamp
			   , book_spread
			   , order_spread
			   , quantity
			   , trade_id
			   , trade_time
			   , broker_buy
			   , broker_sell
			   , direct
			   , aggressor 
			   , case when exec_type + ord_status = '00'
					  then 'Inserção da ordem de '
					  when exec_type + ord_status = '55'
					  then 'Substituição da ordem de '
					  when exec_type + ord_status = 'F1'
					  then 'Trade Parcial da ordem de '
					  when exec_type + ord_status = 'F2'
					  then 'Trade Completo da ordem de '
				end +
				case when side = 1 then 'compra' else 'venda' end AS describe
	        FROM #tb_cycle;

	 INSERT INTO tb_order_buy_layer_hist (order_key,related_order_key, secondary_order_id, buy_timestamp, symbol, position, price, quantity, buy_broker, process_date)
		  SELECT order_key
		  	   , related_order_key
		  	   , secondary_order_id
		  	   , buy_timestamp
		  	   , symbol
		  	   , position
		  	   , price
		  	   , quantity
		  	   , buy_broker
		  	   , process_date 
		    FROM #book_buy

	 INSERT INTO tb_order_sell_layer_hist (order_key,related_order_key, secondary_order_id, sell_timestamp, symbol, position, price, quantity, sell_broker, process_date)
		  SELECT order_key
			   , related_order_key
			   , secondary_order_id
			   , sell_timestamp
			   , symbol
			   , position
			   , price
			   , quantity
			   , sell_broker
			   , process_date 
		    FROM #book_sell																							
/** 
 * Inserts Ocorrência
 */	
DROP TABLE IF EXISTS #issues;
		SELECT 
	  DISTINCT account		
			 , symbol
			 ,process_date
		 INTO #issues
		 FROM #tb_order a 
		 WHERE
		 NOT EXISTS (
		     SELECT 1
		     FROM issues b
		     WHERE 
		         a.account = b.account
		         AND a.symbol = b.symbol
		         AND a.process_date = b.date
		 );

   INSERT INTO issues (account,date,alert_name,symbol,party_id,created_by,[rule],risk,[open],cvm_notification_date,bsm_notification_date,coaf_notification_date,adm_notification_date)
		SELECT 
			account,
			process_date,
			'Layering' AS alert_name,
			symbol,
			(SELECT MAX(party_id) FROM tb_party_id) AS party_id,
			'Admin' AS create_by,
			'Art. 1º e Art. 2º, I e II' AS [rule],
			2 AS risk,
			1 AS [open],
			NULL AS cvm_notification_date,
			NULL AS bsm_notification_date,
			NULL AS coaf_notification_date,
			NULL AS adm_notification_date
		FROM #issues;

------------------------------------------------------------------------------------------------------------------------------
/* LAYERING >>>>> FIM */
------------------------------------------------------------------------------------------------------------------------------
    UPDATE log_ms
    SET dt_end = GETDATE(), duration = CAST(GETDATE() - dt_begin AS TIME), status_description = 'Completed'
    WHERE id_log = @LogID;

END TRY
BEGIN CATCH
	DECLARE @ERROR_MSG VARCHAR(1000) = ERROR_MESSAGE()
    UPDATE log_ms
	   SET dt_end = GETDATE()
		 , duration = CAST(GETDATE() - dt_begin AS TIME)
		 , status_description = 'Error: ' + ERROR_MESSAGE() + ' Error State:' +  cast(ERROR_STATE() as varchar)
     WHERE id_log = @LogID;

			 -- Fechar o cursor após uso
		CLOSE camada_cursor;

		-- Desalocar o cursor para liberar recursos
		DEALLOCATE camada_cursor;

	 RAISERROR(@ERROR_MSG, 16, 1)
END CATCH;