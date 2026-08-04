CREATE proc [dbo].[usp_alert_spoofing]
as
/*
Descrição de alterações
Dia:23/07/2024 Author: Guimo
Inclusão do tratamento de log, para quando rodar novamente o mesmo dia apague das tabelas destino e insira novamente.
Dessa forma evidenciando o reprocessamento pela tabela de log.

Dia:27/07/2024 Author: Guimo
- Alteração da processo de log retirando a condição de completed para reprocessar

Dia:24/09/2024 Author: Guimo
-Inclusão das informações da tabela tb_trade na tabela de tb_order_spo_cycle_hist. Colunas adicionadas trade_time,brokcer_buy,broker_sell,direct e aggressor. Essas colunas só terão resultado quando forem referentes a trade. Exec_typpe = F.

Dia: 13/05/2025 - Guimo 
Inclusão do insert das ocorrencias 

Dia: 23/06/2025 - Guimo 
-- Inclusão da flag de recorrencia no alerta
-- Inclusão da flag de negócio direto (cross)
-- Mudança na lógica do alerta (refizemos baseado no spoofing da b3)
	-- Considerando intervalo de negócios do arquivo de benchmark da bsm

	02/09/2025 - Guimo
	Melhoria de performance incluindo a logica de processar pro blocos.

	30/09/2025 - Edu
	Retirada dos indexs das tabelas temporarias

	16/10/2025 - Guimo e Gobbo
	Atualização permitindo acncelamentoa ntes e depois do trade

	19/03/2026 - Guimo (solicitado por gobbo)
	Trocar o nome da abertura de ocorrencia de FIRA para Admin.


17/06/2026 - Fix: Removido COMMIT/ROLLBACK pois a SP nao abre transacao propria.
              O driver ODBC gerencia a transacao externa; COMMIT aqui causava erro 266 (@@TRANCOUNT 1->0).
*/
------------------------------------------------------------
 --Declare the variable to store the Log ID
DECLARE @LogID INT;
DECLARE @log_process_date DATE = (SELECT max(process_date) FROM tb_order);

BEGIN TRY
    INSERT INTO log_ms (process, dt_exec, dt_begin,status_description,process_date)
    VALUES ('Spoofing', GETDATE(), GETDATE(), 'Started',@log_process_date);
    SET @LogID = SCOPE_IDENTITY();
	
	IF (SELECT COUNT(1) FROM log_ms WHERE process = 'Spoofing' AND process_date = @log_process_date ) > 0
	BEGIN
	
		PRINT 'reprocessing...'

		DELETE FROM tb_order_buy_spo_hist	WHERE process_date = @log_process_date
		DELETE FROM tb_order_sell_spo_hist	WHERE process_date = @log_process_date
		DELETE FROM tb_order_spo_cycle_hist	WHERE process_date = @log_process_date
		DELETE FROM tb_order_spo_hist		WHERE process_date = @log_process_date
		DELETE FROM tb_account_spo_hist		WHERE process_date = @log_process_date
		DELETE FROM issues				    WHERE alert_name = 'Spoofing' AND date = @log_process_date

	END
	ELSE
	BEGIN
		PRINT 'processing...'
	END	

------------------------------------------------------------------------------------------------------------------------------
/* SPOOFING >>>>> INÍCIO */
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
			 , ISNULL(A.price,A.last_px) price
			 , CASE WHEN A.exec_type in('0','4','5') THEN A.quantity WHEN A.exec_type = 'F' THEN A.lastqty END quantity
			 , CASE WHEN A.side = 1 THEN 'C' ELSE 'V'  END side
			 , DATEADD(MILLISECOND,- intervalo_neg_ms ,cast( A.order_timestamp AS TIME(3))) AS min_hora
			 , CAST(A.order_timestamp as time(3)) hora
			 , DATEADD(MILLISECOND, intervalo_neg_ms ,CAST( A.order_timestamp AS TIME(3))) AS max_hora
			 , c.id_bloco
		  INTO #camada_verdadeira
		  FROM tb_order A
		  JOIN #benchmark B
			ON A.symbol = b.symbol
	 LEFT JOIN #cursor_data C
			ON C.process_date = A.process_date
		   AND CAST(A.order_timestamp AS time(3)) between C.hora_inicio and C.hora_fim	

		 WHERE A.source_id = 1
		   AND A.exec_type = 'F'
	  ORDER BY A.symbol
			 , A.order_timestamp;

--CREATE NONCLUSTERED INDEX IDX01
--ON [dbo].[#camada_verdadeira] ([id_bloco])
--INCLUDE ([order_key],[order_id],[account],[exec_type],[ord_status],[secondary_order_id],[order_timestamp],[msg_type],[party_id],[book_timestamp],[book_spread],[order_spread],[trade_id],[price],[quantity],[side],[min_hora],[max_hora])

 DROP TABLE IF EXISTS #tb_entrypoint;
	    SELECT A.process_date
			 , A.order_id			 
			 , A.account
			 , A.symbol
			 , A.exec_type
			 , A.ord_status
			 , isnull(A.price,A.last_px) price
			 , CASE WHEN A.exec_type IN('0','4','5') THEN A.quantity WHEN A.exec_type = 'F' THEN A.lastqty END AS quantity
			 , CASE WHEN A.side = 1 THEN 'C' ELSE 'V'  END AS side
			 , CAST(A.order_timestamp AS TIME(3)) hora
			 , A.secondary_order_id
			 , A.order_key
			 , A.order_timestamp
			 , A.msg_type
			 , A.party_id
			 , A.book_timestamp
			 , A.book_spread
			 , A.order_spread
			 , A.trade_id
			 , c.id_bloco
		  INTO #tb_entrypoint
		  FROM tb_order A
		  	 LEFT JOIN #cursor_data C
			ON  C.process_date = A.process_date
			AND CAST(A.order_timestamp AS time(3)) between C.hora_inicio and C.hora_fim	;

--CREATE NONCLUSTERED INDEX idx_camada_verdadeira_symbol_date
--ON #camada_verdadeira (symbol, process_date)
--INCLUDE (side, min_hora, max_hora);

--CREATE NONCLUSTERED INDEX idx_tb_entrypoint_symbol_date_hora
--ON #tb_entrypoint (symbol, process_date, hora)
--INCLUDE (side);		

/*Junção da camada verdadeira com a falsa (verdadeira + falsa) */
DROP TABLE IF EXISTS #camada_falsa
	   SELECT DISTINCT
			  A.process_date
			, A.symbol
			, A.min_hora
			, A.hora
			, A.max_hora
			, B.side			   AS side_oposto
			, B.price			   AS price_oposto
			, B.hora			   AS hora_oposto
			, B.order_id		   AS order_id_oposto
			, B.account			   AS account_oposto
			, B.exec_type		   AS exec_type_oposto
			, B.ord_status		   AS ord_status_oposto
			, B.quantity		   AS quantity_oposto	
			, B.secondary_order_id AS  secondary_order_id_oposto
			, B.order_key		   AS order_key_oposto
			, B.order_timestamp	   AS order_timestamp_oposto
			, B.msg_type		   AS msg_type_oposot
			, B.party_id		   AS party_id_oposto
			, B.book_timestamp	   AS book_timestamp_oposto
			, B.book_spread		   AS book_spread_oposto
			, B.order_spread	   AS order_spread_oposto
			, B.trade_id		   AS trade_id_oposto
			, A.id_bloco
		 INTO #camada_falsa
		 FROM #camada_verdadeira A
		 JOIN #tb_entrypoint B
		   ON a.symbol = b.symbol
		  AND a.process_date = b.process_date
		  AND a.side <> b.side
		  AND B.hora between A.min_hora and a.max_hora
		  OPTION (RECOMPILE, MAXDOP 4);
	 --ORDER BY A.symbol 
		--	, A.order_id 
		--	, B.hora;

--CREATE NONCLUSTERED INDEX idx_005
--ON [dbo].[#camada_falsa] ([id_bloco])
--INCLUDE ([process_date],[symbol],[hora],[side_oposto],[price_oposto],[hora_oposto],[order_id_oposto],[account_oposto],[exec_type_oposto],[ord_status_oposto],[quantity_oposto],[secondary_order_id_oposto],[order_timestamp_oposto],[book_timestamp_oposto],[book_spread_oposto],[order_spread_oposto],[trade_id_oposto])


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
	

	--CREATE CLUSTERED INDEX CIX_camada_verdadeira
	--ON #camada_verdadeira (process_date, symbol, id_bloco, hora);

	--CREATE NONCLUSTERED INDEX IX_camada_verdadeira_side
	--ON #camada_verdadeira (process_date, symbol, hora, id_bloco)
	--INCLUDE (side);

-------------------------------------------------------
-- Declaração das variáveis
-------------------------------------------------------
DECLARE 
	@id_bloco int;

-------------------------------------------------------
-- Criação do cursor
-------------------------------------------------------
DECLARE camada_cursor CURSOR FAST_FORWARD FOR
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
			a.id_bloco
		FROM #camada_verdadeira A
		JOIN #camada_falsa B
		  ON a.process_date = b.process_date
		 AND a.symbol = b.symbol
		 AND a.side <> b.side_oposto 
		 AND a.hora = b.hora
		 AND a.id_bloco = b.id_bloco
		 and a.id_bloco = @id_bloco
		 and b.id_bloco = @id_bloco
		


DROP TABLE IF EXISTS #qtd_lado_falso;
	   SELECT * 
		 INTO #qtd_lado_falso
		 FROM #camada_falsa_consolidada
	    WHERE hora_oposto <= hora 
		  AND exec_type_oposto not in ('8','4');
	 --ORDER BY order_key 
		--    , book_timestamp_oposto;


/*media da quantidade do book*/
DROP TABLE IF EXISTS #avg_quantity;
	   SELECT A.order_key
			, A.symbol
			, A.process_date
			, 'C' side 
			, isnull(avg(b.quantity) * 2,1) AS avg_quantity_x2 
		 INTO #avg_quantity
		 FROM #qtd_lado_falso A
    LEFT JOIN tb_order_book_buy B
	       ON a.order_key = b.order_key
	    WHERE A.side = 'C' 
	 GROUP BY A.order_key
			, A.symbol
			, A.process_date

        UNION ALL

	   SELECT A.order_key
			, A.symbol
			, A.process_date
			, 'V' side 
			, isnull(avg(b.quantity) * 2,1) AS avg_quantity_x2 
         FROM #qtd_lado_falso A
    LEFT JOIN tb_order_book_sell B
		   ON A.order_key = b.order_key
	    WHERE A.side = 'V' 
     GROUP BY A.order_key
	        , A.symbol
			, A.process_date;



DELETE 
  FROM #camada_falsa_consolidada 
 WHERE EXISTS (SELECT 1 
				 FROM (	
					   SELECT a.symbol 
							, a.order_key
							, a.exec_type 
							, a.quantity
							, a.side
							, a.quantity_oposto 
							, a.exec_type_oposto
							, a.order_id_oposto
							, a.process_date
							, b.avg_quantity_x2
						 
						 FROM #camada_falsa_consolidada A
					LEFT JOIN #avg_quantity B
						   ON a.symbol = b.symbol
						  AND a.process_date = b.process_date
						  AND a.side = b.side
						  AND A.order_key = B.order_key
						  WHERE a.quantity_oposto < b.avg_quantity_x2
					  )X
				 WHERe #camada_falsa_consolidada.order_key = x.order_key
				   ANd #camada_falsa_consolidada.order_id_oposto = x.order_id_oposto
				   ANd #camada_falsa_consolidada.symbol = x.symbol
				   ANd #camada_falsa_consolidada.process_date = x.process_date 
				);

/*verifica se o cliente diminuiu a quantidade depois do trade, apenas substituida*/
  DELETE 
    FROM #camada_falsa_consolidada
   WHERE EXISTS (SELECT 1 
				   FROM ( SELECT A.* , B.avg_quantity_x2
							FROM #camada_falsa_consolidada A
							JOIN #avg_quantity B
							  ON a.order_key = b.order_key 
							 AND a.symbol = b.symbol 
							 AND a.process_date = b.process_date
						   WHERE A.hora_oposto >= A.hora
							 AND A.exec_type_oposto in ('5')
							 AND a.quantity_oposto < b.avg_quantity_x2
						) x
				    WHERE #camada_falsa_consolidada.symbol = x.symbol
					  AND #camada_falsa_consolidada.process_date = x.process_date
					  AND #camada_falsa_consolidada.order_id_oposto = x.order_id_oposto
					  AND #camada_falsa_consolidada.order_key = x.order_key
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
						   AND b.hora >= a.min_hora
						   AND b.hora <= a.max_hora
						   AND b.exec_type = 'F'
						   AND b.side <> a.side
					   )x 
				WHERE #camada_falsa_consolidada.order_key = x.order_key
			      AND #camada_falsa_consolidada.symbol = x.symbol
			      AND #camada_falsa_consolidada.process_date = x.process_date
			   );



/** 
 * Deleta ofertas (camada falsa) cujos trades ocorrem 
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
						WHERE hora_oposto >= hora
						  AND exec_type_oposto = 'F'
					   ) x 
				   WHERE #camada_falsa_consolidada.order_key	   = x.order_key
				     AND #camada_falsa_consolidada.order_id		   = x.order_id
				     AND #camada_falsa_consolidada.account = x.account
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
					  DISTINCT  order_key, order_id , order_id_oposto  
						  FROM #camada_falsa_consolidada 
						 WHERE hora_oposto >= hora
						   AND exec_type_oposto = '0'
					  ) x 
			  WHERE #camada_falsa_consolidada.order_key		  = x.order_key
			    AND #camada_falsa_consolidada.order_id		  = x.order_id
			    AND #camada_falsa_consolidada.order_id_oposto = x.order_id_oposto
			  );
--/** 
-- * Identifica ciclos que contêm PELO MENOS UMA oferta 
-- * criada ou substituída ANTES do evento de trade 
-- */
--DELETE 
--  FROM #camada_falsa_consolidada
-- WHERE NOT EXISTS ( SELECT 1 
--					  FROM (
--							 SELECT 
--						   DISTINCT order_key 
--								  , symbol 
--								  , process_date
--							   FROM #camada_falsa_consolidada
--							  WHERE hora_oposto < hora
--							    AND exec_type_oposto IN ('0','5')
--							) x
--					   WHERE #camada_falsa_consolidada.order_key = x.order_key
--						 AND #camada_falsa_consolidada.symbol = x.symbol
--						 AND #camada_falsa_consolidada.process_date = x.process_date 
--				     );	
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
		 , quantity_oposto
		 , CASE WHEN hora_oposto < hora THEN 'Antes' WHEN hora_oposto > hora THEN 'Depois' ELSE 'Igual' END AS ordem_horas
	  INTO #verificar_pos_trade
	  FROM #camada_falsa_consolidada a
  ORDER BY order_key 
		 , book_timestamp_oposto

 DROP TABLE IF EXISTS #pega_ultima_antes;
		SELECT * 
			 , ROW_NUMBER() OVER(PARTITION BY order_key , order_id_oposto ORDER By hora_oposto DESC) rn
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
	  , quantity_oposto
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
	  , quantity_oposto
	  , ordem_horas 
  FROM #verificar_pos_trade 
 WHERE ordem_horas = 'Depois';
 
 DROP TABLE IF EXISTS #melhora_quantity_pos_trade;
	SELECT * 
		 , LAG(quantity_oposto) over(partition by order_key, order_id_oposto order by hora_oposto) AS quantity_oposto_ant
		 , ISNULL(quantity_oposto - LAG(quantity_oposto) OVER(PARTITION BY order_Key , order_id_oposto ORDER BY hora_oposto),0) AS diff_quantity_ant
				, CASE 
					WHEN side_oposto = 'C' and ISNULL(quantity_oposto - LAG(quantity_oposto) OVER(PARTITION BY order_Key,order_id_oposto order by hora_oposto),0) < 0 THEN 'N'
					WHEN side_oposto = 'C' and ISNULL(quantity_oposto - LAG(quantity_oposto) OVER(PARTITION BY order_Key,order_id_oposto order by hora_oposto),0) = 0 THEN 'M'
					WHEN side_oposto = 'V' and ISNULL(quantity_oposto - LAG(quantity_oposto) OVER(PARTITION BY order_Key,order_id_oposto order by hora_oposto),0) > 0 THEN 'N'
					WHEN side_oposto = 'V' and ISNULL(quantity_oposto - LAG(quantity_oposto) OVER(PARTITION BY order_Key,order_id_oposto order by hora_oposto),0) = 0 THEN 'M'
					ELSE 'S'
				END flag_melhora_quantity
		 INTO #melhora_quantity_pos_trade
		 FROM #verificar_piora_preco 

	    delete 
		  FROM #camada_falsa_consolidada 
		 WHERE EXISTS ( SELECT 1 
						  FROM #melhora_quantity_pos_trade B
						 WHERE #camada_falsa_consolidada.order_key = b.order_key
						   AND #camada_falsa_consolidada.order_id_oposto = b.order_id_oposto
						   AND b.flag_melhora_quantity in( 'S' , 'M'));

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
      ,null
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
		 FROM tb_account_spo_hist 
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
								  FROM tb_account_spo_hist b
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
				 , CASE WHEN b.direct = 1 THEN 1 ELSE 0 END AS flag_cross
				 , CASE WHEN c.account IS NOT NULL THEN 1 ELSE 0 END AS flag_recurrence
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
			     , order_id; 
					
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
			      AND a.symbol   = b.symbol;
	
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
				 , null 							 AS msg_type --A.msg_type_oposot	
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
			    ON A.symbol = b.symbol
			   AND a.process_date = b.process_date
			   AND a.order_key    = b.order_key
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
			   AND a.order_key    = b.order_key
		     --WHERE B.order_key in (select distinct A.order_key_oposto from #camada_falsa) --WHERE order_key in (select distinct related_order_key from #tb_order_layering) 
		  ORDER BY 2 
				 , position;

/** 
 * Inserts Finais
 */	

	 INSERT INTO tb_account_spo_hist (account,symbol,process_date)
		  SELECT account
			   , symbol
			   , process_date 
		    FROM #tb_account;

	 INSERT INTO tb_order_spo_hist (order_key, order_id, secondary_order_id, account, order_timestamp, msg_type, party_id, price, side, symbol, exec_type, ord_status, process_date, book_timestamp, book_spread, order_spread,quantity, flag_cross, flag_recurrence)
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
	 
	INSERT INTO tb_order_spo_cycle_hist (order_key,related_order_key, order_id, secondary_order_id, account, order_timestamp, msg_type, party_id, price, side, symbol, exec_type, ord_status, process_date, book_timestamp, book_spread, order_spread,quantity,trade_id,trade_time,broker_buy,broker_sell,direct,aggressor,describe)
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

	 INSERT INTO tb_order_buy_spo_hist (order_key,related_order_key, secondary_order_id, buy_timestamp, symbol, position, price, quantity, buy_broker, process_date)
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
		    FROM #book_buy;

	 INSERT INTO tb_order_sell_spo_hist (order_key,related_order_key, secondary_order_id, sell_timestamp, symbol, position, price, quantity, sell_broker, process_date)
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
		    FROM #book_sell;																							
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
			'Spoofing' AS alert_name,
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

----------------------------------------------------------------------------------------------------------------------------
/* SPOOFING >>>>> FIM */
----------------------------------------------------------------------------------------------------------------------------
    UPDATE log_ms
    SET dt_end = GETDATE(), duration = CAST(GETDATE() - dt_begin AS TIME), status_description = 'Completed'
    WHERE id_log = @LogID;

END TRY
BEGIN CATCH
	DECLARE @ERROR_MSG VARCHAR(1000) = ERROR_MESSAGE()
    UPDATE log_ms
	   SET dt_end = GETDATE()
		 , duration = CAST(GETDATE() - dt_begin AS TIME)
		 , status_description = 'Error: ' + ERROR_MESSAGE()
     WHERE id_log = @LogID;

		-- Fechar o cursor após uso
		CLOSE camada_cursor;
		
		-- Desalocar o cursor para liberar recursos
		DEALLOCATE camada_cursor;


	 RAISERROR(@ERROR_MSG, 16, 1)
END CATCH;