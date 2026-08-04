CREATE proc [dbo].[usp_alert_omc]
as
/*
Dia:27/07/2024 Author: Guimo
- AlteraÃ§Ã£o da processo de log retirando a condiÃ§Ã£o de completed para reprocessar

Dia:12/11/2024 Author: Guimo
- Ajuste nas tabelas do book acertando o fuso horario com menos 3 horas.

update para acertar o fuso horario retroativo.

		update tb_book_sell_omc_hist
		   set sell_timestamp = dateadd(hour, -3 , sell_timestamp)

       update tb_book_buy_omc_hist
		  set buy_timestamp = dateadd(hour, -3 , buy_timestamp)

DIA 17/02/2024 - Author: Guimo

Por algum motivo as mensagens da tb_trade se repetiram para o trade_id  20 do ativo  FISC11 a unica diferenÃ§a foi a coluna msg_time, sendo assim como n usamos essa coluna coloquei ela como null e adicionei o distinct.

Dia: 13/05/2025 - Guimo 
InclusÃ£o do insert das ocorrencias 

DIA 16/06/2025 - Author: Guimo
-- AletraÃ§Ã£o da verificaÃ§Ã£o da oscilaÃ§Ã£o de 30 segundos para frente e para tras foi alterado puxando informaÃ§Ã£o de intervalo de negocios do benchmark
-- inclusÃ£o das colunas de flag diretos (cross) e recorrencia.
-- inclusÃ£o da coluna de volume
-- InclusÃ£o da coluna creation time com a informaÃ§Ã£o da hora dÃ¡ criaÃ§Ã£o da oferta

Dia: 04/09/2025 - Guimo  e Gobbo
OMC - > preÃ§o e volume de ponto para real; ajuste no campo de data da criaÃ§Ã£o small data para datatime2. Zeramos a flag agressora

dia 10/09/2025
Ajuste na coluna preÃ§o que estava vindo null

19/03/2026 - Guimo (solicitado por gobbo)
Trocar o nome da abertura de ocorrencia de FIRA para Admin.


17/06/2026 - Fix: Removido COMMIT/ROLLBACK pois a SP nao abre transacao propria.
              O driver ODBC gerencia a transacao externa; COMMIT aqui causava erro 266 (@@TRANCOUNT 1->0).
--*/


DECLARE @LogID INT;
DECLARE @log_process_date DATE = (SELECT max(process_date) FROM tb_order);

BEGIN TRY
    INSERT INTO log_ms (process, dt_exec, dt_begin,status_description,process_date)
    VALUES ('Omc', GETDATE(), GETDATE(), 'Started', @log_process_date);
    SET @LogID = SCOPE_IDENTITY();

	IF (SELECT COUNT(1) FROM log_ms WHERE process = 'Omc' AND process_date = @log_process_date) > 0
	BEGIN
	
		PRINT 'reprocessing...'

		DELETE FROM tb_book_buy_omc_hist  WHERE process_date = @log_process_date
		DELETE FROM tb_book_sell_omc_hist WHERE process_date = @log_process_date
		DELETE FROM tb_order_omc_hist	  WHERE process_date = @log_process_date
		DELETE FROM tb_trade_omc_hist     WHERE process_date = @log_process_date
		DELETE FROM tb_metrics_omc_hist   WHERE process_date = @log_process_date
		DELETE FROM tb_account_omc_hist   WHERE process_date = @log_process_date
		DELETE FROM issues				  WHERE alert_name = 'OMC' AND date = @log_process_date

	END
	ELSE
	BEGIN
		PRINT 'processing...'
	END
	
--------------------------------------------------------------------------
--------INFORMAÃ‡Ã•ES DO POSSIVEL OMC


 DROP TABLE IF EXISTS #tb_01;	
		SELECT a.order_key
			 , a.order_id
			 , a.secondary_order_id
			 , a.account
			 , a.symbol
			 , a.side
			 , a.price
			 , a.last_px
			 , a.quantity quantity_order
			 , a.cumqty
			 , a.lastqty
			 , a.exec_type
			 , a.process_date
			 , a.book_timestamp
			 , a.book_spread
			 , a.order_spread
			 , a.trade_id
			 , a.trading_session_sub_id 
			 , b.aggressor
			 , b.trade_time
			 , b.quantity quantity_trade
			 , b.broker_buy
			 , b.broker_sell
			 , case when a.trading_session_sub_id in (18,21,101) then 1 else 0 end flag_auction 
		
		  INTO #tb_01
		  FROM tb_order a WITH(NOLOCK) 
	INNER JOIN tb_trade b WITH(NOLOCK) 
	        ON a.trade_id	  = b.trade_id
	       AND a.symbol		  = b.symbol
	       AND a.process_date = b.process_date
		 WHERE a.source_id = 2 
		   AND a.exec_type = 'F';


	DROP TABLE IF EXISTS #creation
		   SELECT 
		 DISTINCT A.order_id  
		        , DATEADD(HOUR,-3,MIN(B.order_timestamp)) creation_timestamp 
			 INTO #creation
			 FROM #tb_01 A
			 JOIN tb_entrypoint B 
			   ON a.order_id = b.order_id
			WHERE b.exec_type in ('0','5')
		 GROUP BY A.order_id 



 DROP TABLE IF EXISTS #tb_buy;
		SELECT order_key
			 , order_id
			 , secondary_order_id
			 , account
			 , symbol
			 , side
			 , price
			 , last_px
			 , quantity_order
			 , cumqty
			 , lastqty
			 , exec_type
			 , process_date
			 , book_timestamp
			 , book_spread
			 , order_spread
			 , trade_id
			 , trading_session_sub_id 
			 , aggressor
			 , trade_time
			 , quantity_trade
			 , broker_buy
			 , broker_sell
			 , flag_auction
		
		  INTO #tb_buy
		  FROM #tb_01 
		 WHERE side = 1;

 DROP TABLE IF EXISTS #tb_sell;	
		SELECT order_key
			 , order_id
			 , secondary_order_id
			 , account
			 , symbol
			 , side
			 , price
			 , last_px
			 , quantity_order
			 , cumqty
			 , lastqty
			 , exec_type
			 , process_date
			 , book_timestamp
			 , book_spread
			 , order_spread
			 , trade_id
			 , trading_session_sub_id 
			 , aggressor
			 , trade_time
			 , quantity_trade
			 , broker_buy
			 , broker_sell
			 , flag_auction 
		
		  INTO #tb_sell
		  FROM #tb_01 
		 WHERE side = 2;

DROP TABLE IF EXISTS #tb_02;
	  SELECT A.account
		   , A.symbol
		   , A.exec_type
		   , A.quantity_trade
		   , A.book_spread		  AS book_spread_buy
		   , B.book_spread		  AS book_spread_sell
		   , A.order_spread		  AS order_spread_buy
		   , B.order_spread		  AS order_spread_sell
		   , A.trade_id
		   , A.order_key		  AS order_key_buy
		   , B.order_key		  AS order_key_sell
		   , A.order_id			  AS order_id_buy
		   , B.order_id			  AS order_id_sell
		   , A.secondary_order_id AS  secondary_order_id_buy
		   , B.secondary_order_id AS  secondary_order_id_sell
		   , A.aggressor
		   , A.flag_auction
		   , A.trade_time
		   , A.broker_buy
		   , A.broker_sell
		   , A.price
		   , a.process_date
		INTO #tb_02
		FROM #tb_buy A
  INNER JOIN #tb_sell B
		  ON A.account		= B.account
		 AND A.symbol		= B.symbol
		 AND A.process_date = B.process_date
		 AND A.trade_id		= B.trade_id;

		
---------------------------------------------------------------
---CALCULO DA MÃ‰DIA E DESVIO DA QUANTIDADE DO BOOK

   DROP TABLE IF EXISTS #tb_03;
		  SELECT 
		DISTINCT a.account, B.symbol , B.quantity , B.position , B.secondary_order_id , B.order_key, a.process_date
			INTO #tb_03
		    FROM #tb_02 A
	  INNER JOIN tb_order_book_buy B WITH(NOLOCK) 
		      ON A.order_key_buy = B.order_key

		   UNION ALL
	
		  SELECT 
		DISTINCT a.account,C.symbol , C.quantity , C.position , C.secondary_order_id ,C.order_key, a.process_date
		    FROM #tb_02 A
	  INNER JOIN tb_order_book_sell C WITH(NOLOCK)
		      ON A.order_key_buy = C.order_key;

	 INSERT INTO #tb_03
		  SELECT 
		DISTINCT a.account, B.symbol , B.quantity , B.position , B.secondary_order_id , B.order_key , a.process_date
			
		    FROM #tb_02 A
	  INNER JOIN tb_order_book_buy B WITH(NOLOCK) 
		      ON A.order_key_sell = B.order_key
	
		   UNION ALL
	
		  SELECT 
		DISTINCT a.account ,C.symbol , C.quantity , C.position , C.secondary_order_id ,C.order_key, a.process_date
		    FROM #tb_02 A
	  INNER JOIN tb_order_book_sell C WITH(NOLOCK)
		      ON A.order_key_sell = C.order_key;			  

  DROP TABLE IF EXISTS #tb_metrics;
		 SELECT symbol,order_key,account, avg(quantity) avg_quantity
		 	  , stdev(quantity)stdev_quantity 
			  , process_date
		   INTO #tb_metrics
		   FROM #tb_03
		   GROUP BY symbol,order_key,account,process_date;

DROP TABLE IF EXISTS #avg;
	   SELECT a.account
			, a.symbol
			, a.exec_type
			, a.quantity_trade
			, a.book_spread_buy
			, a.book_spread_sell
			, a.order_spread_buy
			, a.order_spread_sell
			, a.trade_id
			, a.order_key_buy
			, a.order_key_sell
			, a.order_id_buy
			, a.order_id_sell
			, a.secondary_order_id_buy
			, a.secondary_order_id_sell
			, a.aggressor
			, a.flag_auction
			, a.trade_time
			, a.broker_buy
			, a.broker_sell
			, b.avg_quantity
			, b.stdev_quantity
			, a.price
			, null flag_oscilation
			, a.process_date
			, case when a.quantity_trade > (avg_quantity + (3 * stdev_quantity)) then 1 else 0 end flag_quantity
		 INTO #avg
	     FROM #tb_02 A
	LEFT JOIN #tb_metrics B
	       ON a.symbol  = b.symbol
	      AND a.account = b.account
	      AND a.order_key_buy = b.order_key
	    
	   --comento o where acima para conseguir testar o cÃ³digo pois com a carga do dia 13/06 todo mundo cai nesse filtro
  
  DECLARE @account BIGINT
		, @symbol VARCHAR(30)
		, @trade_id BIGINT
		, @order_key_buy BIGINT
		, @order_key_sell BIGINT
		, @order_id_buy BIGINT
		, @order_id_sell BIGINT
		, @secondary_order_id_buy BIGINT
		, @secondary_order_id_sell BIGINT
		, @trade_time TIME
		, @price DECIMAL(20,2)

DECLARE cursor_trade CURSOR FOR
	SELECT account 
		 , symbol 
		 , trade_id 
		 , order_key_buy 
		 , order_key_sell 
		 , order_id_buy 
		 , order_id_sell 
		 , secondary_order_id_buy 
		 , secondary_order_id_sell 
		 , trade_time 
		 , price  
	  FROM #avg
	 WHERE flag_auction = 0

OPEN cursor_trade

FETCH NEXT FROM cursor_trade INTO @account,@symbol,@trade_id,@order_key_buy,@order_key_sell, @order_id_buy,@order_id_sell,@secondary_order_id_buy,@secondary_order_id_sell,@trade_time,@price

WHILE @@FETCH_STATUS = 0
BEGIN
	declare @intervalo int;

		SELECT @intervalo =
			DATEPART(HOUR, menor_media_intervalo_negs) * 3600000 +    -- Horas em milissegundos (1 hora = 3600 seg * 1000 ms/seg)
			DATEPART(MINUTE, menor_media_intervalo_negs) * 60000 +    -- Minutos em milissegundos (1 min = 60 seg * 1000 ms/seg)
			DATEPART(SECOND, menor_media_intervalo_negs) * 1000 +    -- Segundos em milissegundos (1 seg = 1000 ms/seg)
			DATEPART(MILLISECOND, menor_media_intervalo_negs)
		FROM
			tb_benchmark
		where symbol = @symbol


    -- Aqui vocÃª pode adicionar a lÃ³gica que deseja aplicar a cada registro
    DECLARE @trade_time_up30   TIME = DATEADD(MILLISECOND, @intervalo,@trade_time)
		  , @trade_time_down30 TIME = DATEADD(MILLISECOND,-@intervalo,@trade_time) 

	PRINT 'Account: ' + ISNULL(CAST(@account AS VARCHAR), '') + 
          ', Symbol: ' + ISNULL(@symbol, '') + 
          ', Trade ID: ' + CAST(@trade_id AS VARCHAR) + 
          ', Order Key Buy: ' + CAST(@order_key_buy AS VARCHAR) + 
          ', Order Key Sell: ' + CAST(@order_key_sell AS VARCHAR) + 
          ', Order ID Buy: ' + CAST(@order_id_buy AS VARCHAR) + 
          ', Order ID Sell: ' + CAST(@order_id_sell AS VARCHAR) + 
          ', Secondary Order ID Buy: ' + CAST(@secondary_order_id_buy AS VARCHAR) + 
          ', Secondary Order ID Sell: ' + CAST(@secondary_order_id_sell AS VARCHAR) + 
          ', Trade Time: ' + ISNULL(CAST(@trade_time AS VARCHAR), '') + 
          ', Price: ' + CAST(@price AS VARCHAR) + 
          ', Trade Time Ip 30: ' + ISNULL(CAST(@trade_time_up30 AS VARCHAR), '') + 
          ', Trade Time Down 30: ' + ISNULL(CAST(@trade_time_down30 AS VARCHAR), '')

		  DECLARE @trade_id_min_before BIGINT 
		         ,@trade_id_max_before BIGINT
				 ,@price_before_1  DECIMAL(20,2)
			     ,@price_before_2 DECIMAL(20,2)
				 ,@trade_id_max_after BIGINT 
				 ,@price_after_1 decimal(20,2)

   DROP TABLE IF EXISTS #before;
		  SELECT  symbol
				, task
				, price
				, LAG(Price, 1, price) OVER (PARTITION BY Symbol ORDER BY trade_id) AS previous_price
				, ABS(price - LAG(Price, 1, price) OVER (PARTITION BY Symbol ORDER BY trade_id)) oscilation
				, quantity
				, trade_time
				, broker_buy
				, broker_sell
				, trade_id
				, direct
				, aggressor
				, process_date
			INTO #before
			FROM tb_trade
		   WHERE symbol		 = @symbol 
		     AND trade_time >= @trade_time_down30 
			 AND trade_time < @trade_time		 
	
   DROP TABLE IF EXISTS #after;			 
		 SELECT symbol
				, task
				, price
				, LAG(Price, 1, price) OVER (PARTITION BY Symbol ORDER BY trade_id) AS previous_price
				, abs(price - LAG(Price, 1, price) OVER (PARTITION BY Symbol ORDER BY trade_id)) oscilation
				, quantity
				, trade_time
				, broker_buy
				, broker_sell
				, trade_id
				, direct
				, aggressor
				, process_date
		   INTO #after
		   FROM tb_trade
		  WHERE symbol = @symbol 
		    AND trade_time >= @trade_time 
		    AND trade_time <= @trade_time_up30
		 
	  DECLARE @oscilation_before DECIMAL(17,3) , @oscilation_after DECIMAL(17,3)
	   SELECT @oscilation_before = isnull(avg(oscilation),0) from #before
	   SELECT @oscilation_after  = isnull(avg(oscilation),0) From #after


	   IF @oscilation_after > @oscilation_before
	   BEGIN

		UPDATE #avg
		   SET flag_oscilation = 1 --SIM
		 WHERE symbol = @symbol
		   AND trade_id= @trade_id

	   END
	   ELSE
	   BEGIN

	   		UPDATE #avg
		   SET flag_oscilation = 0 --NÃƒO
		 WHERE symbol = @symbol
		   AND trade_id= @trade_id

	   END


    FETCH NEXT FROM cursor_trade INTO  @account,@symbol,@trade_id,@order_key_buy,@order_key_sell, @order_id_buy,@order_id_sell,@secondary_order_id_buy,@secondary_order_id_sell,@trade_time,@price
END

CLOSE cursor_trade
DEALLOCATE cursor_trade

DROP TABLE IF EXISTS #omc;
	   SELECT account
			, symbol
			, exec_type
			, quantity_trade quantity
			, order_key_buy order_key
			, price
			, trade_id
			, avg_quantity
			, stdev_quantity
			, flag_auction
			, flag_oscilation 
			, 0 flag_aggressor 
			, flag_quantity
			, process_date
		 INTO #omc
	     FROM #avg 


  DROP TABLE IF EXISTS #RESULT;
		 SELECT account
			  , symbol
			  , exec_type
			  , quantity
			  , avg_quantity -- book
			  , cast(stdev_quantity as decimal(20,4))stdev_quantity --book
			  , price
			  , order_key
			  , trade_id
			  , flag_auction
			  , flag_oscilation 
			  , flag_aggressor 
			  , flag_quantity
			  , process_date
		   INTO #RESULT
		   FROM #omc	
	
		  --order_key que serÃ£o salvas para historico
  DROP TABLE IF EXISTS #order_key;
		 SELECT a.order_key , a.process_date
		   into #order_key
		   FROM tb_order a 
	 INNER JOIN #RESULT b 
			 ON a.trade_id = b.trade_id 
			AND a.symbol = b.symbol 
			AND a.process_date = b.process_date




-----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
DROP TABLE IF EXISTS #recorrencia;
	  DECLARE @process_date DATE = (SELECT max(process_date) FROM tb_entrypoint)
	   SELECT 
	 DISTINCT account
			, process_date 
		 INTO #recorrencia
		 FROM tb_account_omc_hist 
		WHERE process_date >= dateadd(day,-180, @process_date) 
		  AND process_date < @process_date;


	--	  --tb_account_omc_hist[
    INSERT INTO tb_account_omc_hist(account,symbol,process_date)
		 SELECT 
	   DISTINCT account
			  , symbol
			  , process_date
		   FROM #RESULT  a 
		  WHERE NOT EXISTS (SELECT 1 
							   FROM tb_account_omc_hist b 
							  WHERE a.account = b.account 
							    AND a.symbol = b.symbol 
								AND a.process_date = b.process_date)
   DROP TABLE IF EXISTS #issue;
		 SELECT 
	   DISTINCT account 
			  , symbol
			  , process_date
		   INTO #issue
		   FROM #RESULT  a 
		  WHERE NOT EXISTS (SELECT 1 
							   FROM issues b 
							  WHERE a.account = b.account 
							    AND a.symbol = b.symbol 
								AND a.process_date = b.date)

								 
	  --tb_metrics_omc_hist
	 INSERT INTO tb_metrics_omc_hist (account,symbol,trade_id,flag_auction,flag_oscillation,flag_aggressor,flag_quantity,process_date,flag_cross,flag_recurrence)
		 SELECT 
	   DISTINCT  a.account
			  , a.symbol
			  , a.trade_id
			  , a.flag_auction
			  , isnull(a.flag_oscilation,0)flag_oscilation
			  , a.flag_aggressor
			  , a.flag_quantity
			  , a.process_date 
			  , case when b.direct = 1 then 1 else 0 end flag_cross
			  , case when c.account is not null then 1 else 0 end flag_recurrence
		   from #RESULT  A
		   join tb_trade B
			on a.trade_id = b.trade_id
		   and a.process_date = b.process_date
		   and a.symbol = b.symbol
		   left join #recorrencia C
		   on a.account = c.account
		
	
	--	--tb_trade_omc_hist

	 INSERT INTO tb_trade_omc_hist(msg_time, header, symbol, task, price, quantity,avg_quantity,stdev_quantity, trade_time, broker_buy, broker_sell, trade_id, direct, aggressor, process_date,volume)
		   SELECT 
		 DISTINCT NULL msg_time --a.msg_time
			   ,a.header
			   ,a.symbol
			   ,a.task
			   --,a.price
			    ,  CASE 
					WHEN a.symbol LIKE 'WIN%' THEN 
						(a.price * 0.20) 
	
					WHEN a.symbol LIKE 'WDO%' THEN 
						 (a.price * 10.00) 
	
					WHEN a.symbol LIKE 'BIT%' THEN 
						(a.price * 0.10) 
				ELSE A.price  END  price
			   ,a.quantity
			   ,b.avg_quantity
			   ,b.stdev_quantity
			   ,a.trade_time
			   ,a.broker_buy
			   ,a.broker_sell
			   ,a.trade_id
			   ,a.direct
			   ,a.aggressor
			   ,a.process_date
			   --,a.price * a.quantity volume
			   ,  CASE 
					WHEN a.symbol LIKE 'WIN%' THEN 
						(a.price * a.quantity) * 0.20
	
					WHEN a.symbol LIKE 'WDO%' THEN 
						 (a.price * a.quantity) * 10.00
	
					WHEN a.symbol LIKE 'BIT%' THEN 
						(a.price * a.quantity) * 0.10
				ELSE (a.price * a.quantity) END AS volume
		   FROM tb_trade a 
	 INNER JOIN #RESULT b 
			 ON a.trade_id = b.trade_id 
			AND a.symbol = b.symbol 
			AND a.process_date = b.process_date	

	--	--tb_order_omc_hist
	INSERT INTO tb_order_omc_hist
		 SELECT DISTINCT a.order_key
			   ,a.order_id
			   ,a.secondary_order_id
			   ,a.account
			   ,DATEADD(HOUR,-3,a.order_timestamp) AS  order_timestamp
			   ,a.msg_type
			   ,a.party_id
			   --,a.price
			   ,  CASE 
					WHEN a.symbol LIKE 'WIN%' THEN 
						(a.price * 0.20) 
	
					WHEN a.symbol LIKE 'WDO%' THEN 
						 (a.price * 10.00) 
	
					WHEN a.symbol LIKE 'BIT%' THEN 
						(a.price * 0.10) 

					ELSE A.PRICE 
				END  price
			   --,a.last_px
			   ,  CASE 
					WHEN a.symbol LIKE 'WIN%' THEN 
						(a.last_px * 0.20) 
	
					WHEN a.symbol LIKE 'WDO%' THEN 
						 (a.last_px * 10.00) 
	
					WHEN a.symbol LIKE 'BIT%' THEN 
						(a.last_px  * 0.10 )
					ELSE A.last_px
				END  last_px
			   ,a.quantity
			   ,a.cumqty
			   ,a.lastqty
			   ,a.leavesqty
			   ,a.side
			   ,a.symbol
			   ,a.exec_type
			   ,a.ord_status
			   ,a.process_date
			   ,DATEADD(HOUR,-3,a.book_timestamp) AS book_timestamp
			   ,a.book_spread
			   ,a.order_spread
			   ,a.trade_id
			   ,a.source_id
			   ,a.trading_session_sub_id
			   ,c.creation_timestamp
		   FROM tb_order a 
	 INNER JOIN #RESULT b 
			 ON a.trade_id = b.trade_id 
			AND a.symbol = b.symbol 
			AND a.process_date = b.process_date		
	  LEFT JOIN #creation C
	  on a.order_id = c.order_id
	
	

	----tb_book_buy_omc_hist

	INSERT INTO tb_book_buy_omc_hist(order_key, secondary_order_id, buy_timestamp, symbol, position, price, quantity, buy_broker, process_date)
		 SELECT distinct a.order_key
			   ,a.secondary_order_id
			   ,dateadd(hour,-3,a.buy_timestamp) as buy_timestamp
			   ,a.symbol
			   ,a.position
			   ,a.price
			   ,a.quantity
			   ,a.buy_broker
			   ,a.process_date
		   FROM tb_order_book_buy a
	 INNER JOIN #order_key b
		     ON a.order_key = b.order_key
		    AND a.process_date = b.process_date
	  
	  --tb_book_sell_omc_hist
	INSERT INTO tb_book_sell_omc_hist(order_key, secondary_order_id, sell_timestamp, symbol, position, price, quantity, sell_broker, process_date)
		 SELECT DISTINCT a.order_key
			   ,a.secondary_order_id
			   ,dateadd(hour,-3,a.sell_timestamp) as sell_timestamp
			   ,a.symbol
			   ,a.position
			   ,a.price
			   ,a.quantity
			   ,a.sell_broker
			   ,a.process_date
		   FROM tb_order_book_sell a
	 INNER JOIN #order_key b
		     ON a.order_key = b.order_key
		    AND a.process_date = b.process_date;

	INSERT INTO issues (account,date,alert_name,symbol,party_id,created_by,[rule],risk,[open],cvm_notification_date,bsm_notification_date,coaf_notification_date,adm_notification_date)
		 SELECT 
			account,
			process_date,
			'OMC' AS alert_name,
			symbol,
			(SELECT MAX(party_id) FROM tb_party_id) AS party_id,
			'Admin' AS create_by,
			'Art. 1Âº e Art. 2Âº, I e IV' AS [rule],
			2 AS risk,
			1 AS [open],
			NULL AS cvm_notification_date,
			NULL AS bsm_notification_date,
			NULL AS coaf_notification_date,
			NULL AS adm_notification_date
		FROM #issue;		

   UPDATE log_ms
    SET dt_end = GETDATE(), duration = CAST(GETDATE() - dt_begin AS TIME), status_description = 'Completed'
    WHERE id_log = @LogID;

END TRY
BEGIN CATCH
	DECLARE @ERROR_MSG VARCHAR(1000) = ERROR_MESSAGE()
    UPDATE log_ms
	   SET dt_end = GETDATE()
		 , duration = CAST(GETDATE() - dt_begin AS TIME)
		 , status_description = 'Error: ' + ERROR_MESSAGE() + ' Error State:' + cast(ERROR_STATE() as varchar)
     WHERE id_log = @LogID;

	IF CURSOR_STATUS('global', 'cursor_trade') >= -1
	BEGIN
	    CLOSE cursor_trade;
	    DEALLOCATE cursor_trade;
	END

	 RAISERROR(@ERROR_MSG, 16, 1)
END CATCH;