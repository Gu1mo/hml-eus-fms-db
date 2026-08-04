CREATE PROC [dbo].[usp_alert_oscillation]
AS

/*
Descrição de alterações
Dia:24/07/2024 Author: Guimopro
Criação da tabela tb_line_chart_osc_hist, com as amplitudes para incluir no gráfico.
Ajuste do calculo das amplitudes onde havia um erro. (linha: 143)
Inclusão da coluna Price

Dia:27/07/2024 Author: Guimo
- Alteração da processo de log retirando a condição de completed para reprocessar

Dia:08/11/2024 Author: Guimo e Salomão
Adicionado a regra de porpoção comparando o volume financeiro do mercado contra o volume financeiro do cliente

Dia:02/12/2024 Author: Guimo e Gobbo
Tinha casos em que a proporção era menor que a do mercado estava caindo agora foi ajustado o delete incluindo no where a condição  and a.symbol = #metrics_osc_hist.symbol

	delete
		  from #metrics_osc_hist 
		 where  not exists (select 1 from #prop a where a.account = #metrics_osc_hist.account and a.symbol = #metrics_osc_hist.symbol)
13/12/2024
tirou  >= para >

07/01/2025 - Eduardo Teixeira
Alteração de >= para > - WHERE price > (wtavg_price + (3 * wtstdev_price))

16/01/2025 - Eduardo Teixeira e Luiz Gobbo
Alteramos: 
Comentamos filtro do ratio
Comentamos filtro de pts
ajustamos Prop_Client usando a quantidade correta (trocou quantity para lastqty)
Criamos uma nova temporária chamada #pre_prop_client e substituindo a tabela #metrics_osc_hist no processo de criação dos dados de prop_client pois estava duplicando os dados.
Ajustamos o prop_mercado tirando o desvio do numerador
Adicionamos aos blocos de preço que a diferença do preço do cliente com o mercado + 3*desvio precisa ser maior que 5 centavos.
Colocamos dois filtros no final de Prop_client > 25% 
E desvio do mercado > que 0

20/01/2025 - Author Guimo e Gobbo
Condições de cada bloco adicionando a regra  + 0.05

21/01/2025 - Author Guimo e Gobbo
Alterei a função lag do previus price quando não havia correspondente colocava 0 , agora entra como null e o cliente não é alertado.
Identificamos que no marketdata do dia 2025_17_01 o ativo AAGR11  começa com trade_id a partir do 50 sendo que no dropcopy começa a partir do 40.
Precisamos entender o porque desse comportamento, vamos seguir com a correção eliminando esse caso já que não era para cair.

03/02/2025 - Autores: Guimo e Gobbo

Alteração no cálculo da coluna Ratio na rotina que carrega a tabela #liq_metrics, responsável por alimentar a tabela tb_symbol_osc_hist.

Antes:
  CAST(SQRT(trade_count / NULLIF(financial_volume,0)) * 100 AS DECIMAL(17,2))
Depois:
  POWER(trade_count / 1000.00, 3) / (POWER(NULLIF(financial_volume, 0), 0.01) * 1000) 

  24/03/2025 - Author: Guimo

  Alteração da coluna quantity de int para bigint, pois o ativo FNAM11  apresentou quantidade elevadas e ao realizar calculos dos blocos da linha 240 e 264 dava erro pois ultrapassava o limite.
Dia: 13/05/2025 - Guimo 
Inclusão do insert das ocorrencias 

Dia: 13/08/2025 - Guimo e Gobinaldo
-	Corrigimos a conta das médias ponderadas.
-	Corrigimos a média do mercado que estava como inteiro e vinha zero ou 1.
-	Fizemos um paleativo, pois na tb_quote está vindo preço de abertura, fechamento, min e max zerados para alguns ativos.
-	Lembrar que o oscilação não roda para WIN e WDO.
-	Ajustamos o preço que é para pegar a coluna last px, antes pegava price
-	Ajustamos a proporção média do cliente e mercado, fazendo o paleativo citado anteriormente.
-	Prop_client > 5% ajustamos para 5%, verificar se cair mt gente, podemos mexer nesse valor

29/08/2025 - Guimo e Gobbo
Band-Aid na coluna trade count 


18/09/2025 - Guimo e Gobbo
alterando o filtro de proporção do cliente para ser >= a do mercado e alteramos o tamanho das colunas de proporção da tb_metrics_osc_hist.


02/01/2026 - Guimo
Melhoria na tabela tb_line_chart_osc_hist para salvar dados apenas de clientes alertados pois está salvando mercado completo.

15/01/2026 - Teixeira 
Ajuste de datatype da coluna financial_volume para DECIMAL(38, 6) visando eliminar erros de Arithmetic Overflow e garantir 
a integridade de grandes volumes financeiros.

16/01/2026 - Teixeira 
Migração das colunas de quantidade para BIGINT para evitar erros de estouro (overflow) causados pela alta volumetria do ativo AZUL53.

02/02/2026 - Guimo e Gobbinaldo
Troca a tb_quote e utilizar a tb_trade para utilizar as informações abertura, fechamento, min , max e avg.

11/02/2026 - Guimo
Ajuste nos comandos inserts qu ficaram comentados na ultima atualização

19/03/2026 - Guimo (solicitado por gobbo)
Trocar o nome da abertura de ocorrencia de FIRA para Admin.


17/06/2026 - Fix: Removido COMMIT/ROLLBACK pois a SP nao abre transacao propria.
              O driver ODBC gerencia a transacao externa; COMMIT aqui causava erro 266 (@@TRANCOUNT 1->0).
**/				

DECLARE @LogID INT;				
DECLARE @log_process_date DATE = (SELECT max(process_date) FROM tb_order);

BEGIN TRY
    INSERT INTO log_ms (process, dt_exec, dt_begin,status_description,process_date)
    VALUES ('Oscillation', GETDATE(), GETDATE(), 'Started',@log_process_date);
    SET @LogID = SCOPE_IDENTITY();;

	IF (SELECT COUNT(1) FROM log_ms WHERE process = 'Oscillation' AND process_date = @log_process_date) > 0
	BEGIN

		PRINT 'reprocessing...'

		DELETE FROM tb_order_osc_hist	   WHERE process_date = @log_process_date
		DELETE FROM tb_metrics_osc_hist	   WHERE process_date = @log_process_date
		DELETE FROM tb_account_osc_hist	   WHERE process_date = @log_process_date
		DELETE FROM tb_symbol_osc_hist	   WHERE process_date = @log_process_date
		DELETE FROM tb_line_chart_osc_hist WHERE process_date = @log_process_date
		DELETE FROM issues				   WHERE alert_name = 'Oscilação de Preços' AND date = @log_process_date

	END
	ELSE
	BEGIN
		PRINT 'processing...'
	END 
	------------------------------------------------------------------------
	------------------------------------------------------------------------

		/*
			Guarda as informações de mercado, principalmente nessa etapa é identificado o preço negociado imediatamente anterior 
		*/
		 DROP TABLE IF EXISTS #trade_id;
				SELECT msg_time
					 , header
					 , symbol
					 , task
					 , price as price
					 , quantity
					 , trade_time
					 , broker_buy
					 , broker_sell
					 , trade_id
					 , direct
					 , aggressor
					 , process_date
					 , LAG(trade_id, 1) OVER (PARTITION BY symbol ORDER BY trade_id) AS previous_trade_id
					 , LAG(price, 1)    OVER (PARTITION BY symbol ORDER BY trade_id) AS previous_price
		
				  INTO #trade_id
				  FROM tb_trade   WITH(NOLOCK)
				 --WHERE task= 'A'
				 WHERE price >= 0
				 OPTION (RECOMPILE, MAXDOP 4);

				 CREATE NONCLUSTERED INDEX IDX_001
				 ON [dbo].[#trade_id] ([symbol],[trade_id])
				 INCLUDE ([previous_trade_id],[previous_price])

		DROP TABLE IF EXISTS #ATIVOS;
		SELECT DISTINCT SYMBOL INTO #ATIVOS FROM tb_order		   		
		/*
			Interday e intraday
		*/	
		
			DROP TABLE IF EXISTS #close_trade_id;
		  SELECT symbol 
			   , MAX(trade_id) AS close_trade_id 
			   , process_date 
		    INTO #close_trade_id 
		    FROM tb_trade 
			 WHERE price >= 0
		GROUP BY process_date
			   , symbol;
	
	DROP TABLE IF EXISTS #market;
		   SELECT a.symbol
				, ISNULL(CAST(MAX(CASE WHEN trade_id = 10 THEN price END) AS DECIMAL(17,2)),MAX(c.open_price))	AS open_price
				, CAST(MAX(CASE WHEN trade_id = b.close_trade_id THEN price END) AS DECIMAL(17,2))			    AS close_price
				, CAST(c.yesterday_close_price	 AS DECIMAL(17,2))											    AS yesterday_close_price
				, CAST(MIN(price)AS DECIMAL(17,4))															    AS min_price
				, CAST(MAX(price)AS DECIMAL(17,4))															    AS max_price 
				, CAST(AVG(price)AS DECIMAL(17,4))															    AS avg_price
				, CAST(((CAST(MAX(CASE WHEN trade_id = b.close_trade_id THEN price END) AS DECIMAL(17,2)) / nullif(ISNULL(CAST(MAX(CASE WHEN trade_id = 10 THEN price END) AS DECIMAL(17,2)),MAX(c.open_price)),0) ) - 1) AS DECIMAL(17,4))          AS intraday
				, CAST(((yesterday_close_price / nullif(ISNULL(CAST(MAX(CASE WHEN trade_id = 10 THEN price END) AS DECIMAL(17,2)),MAX(c.open_price)),0)) - 1) AS DECIMAL(17,4)) AS interday
			   	, (CAST(MAX(price)AS DECIMAL(17,4)) - CAST(MIN(price)AS DECIMAL(17,4)))																							AS market_amplitude --amplitude_mercado
				, sum(CAST(a.price * a.quantity        AS DECIMAL(38, 6)))																										AS financial_volume
				, count(distinct trade_id)																																		AS trade_count			    
			    , a.process_date																																				AS symbol_timestamp
			 INTO #market--#mercado
		    FROM tb_trade  A  WITH(NOLOCK) 
		    JOIN #close_trade_id B
		      ON a.symbol = b.symbol
		     AND a.process_date = b.process_date
	   LEFT JOIN tb_quote C
			  ON a.process_date = c.symbol_timestamp
			 AND a.symbol = c.symbol
			   WHERE a.price >= 0
		GROUP BY a.symbol 
			   , a.process_date
			   , yesterday_close_price
		  OPTION (RECOMPILE, MAXDOP 4);

		
		
		--DROP TABLE IF EXISTS #market;--#mercado; 
		--	   SELECT a.symbol
		--	   	    , CAST(a.open_price				 AS DECIMAL(17,2)) AS open_price
		--	   	    , CAST(a.close_price			 AS DECIMAL(17,2)) AS close_price
		--	   	    , CAST(a.yesterday_close_price	 AS DECIMAL(17,2)) AS yesterday_close_price
		--	   	    , CAST(a.min_price				 AS DECIMAL(17,2)) AS min_price
		--	   	    , CAST(a.max_price				 AS DECIMAL(17,2)) AS max_price
		--	   	    , CAST(a.avg_price				 AS DECIMAL(17,2)) AS avg_price
		--	   	    , CAST(((close_price / nullif(open_price,0) ) - 1) AS DECIMAL(17,4))          AS intraday
		--	   	    , CAST(((yesterday_close_price / nullif(open_price,0)) - 1) AS DECIMAL(17,4)) AS interday
		--	   	    , (max_price - min_price) market_amplitude --amplitude_mercado
		--			, CAST(a.financial_volume        AS DECIMAL(38, 6)) AS financial_volume
		--			, a.trade_count
		--			, symbol_timestamp
		--	    --INTO #market--#mercado
		--	    FROM tb_quote a WITH(NOLOCK) 
		--  INNER JOIN #ATIVOS b
		--		  ON a.symbol = b.symbol
		--		  where a.symbol = 'VALEX670'
		--		  OPTION (RECOMPILE, MAXDOP 4);



			/* Band-Aid para tb_quote inicio*/ --13 08 2025

			--ABERTURA inicio--
	drop table if exists #tb_quote_band_aid_open;
		   select 
		 distinct symbol 
			 into #tb_quote_band_aid_open
			 From #market 
			where open_price = 0; 

	drop table if exists #min_trade_id;
		   select symbol 
				, min(trade_id) AS trade_id 
			into #min_trade_id 
			From tb_trade 
			 WHERE price >= 0
		group by symbol;

	drop table if exists #paliativo;
		   select a.symbol 
				,  b.trade_id 
				, a.price AS open_price
			into #paliativo
			 From tb_trade A
			 join #min_trade_id B 
			   on a.symbol = b.symbol
			  and a.trade_id = b.trade_id
			 join #tb_quote_band_aid_open C
			   on a.symbol = c.symbol
			  and a.symbol = b.symbol
			    WHERE a.price >= 0;			  

			  update #market
			  set open_price = b.open_price
			  From #market A
			  join #paliativo b
			  on a.symbol = b.symbol
			  where a.open_price = 0;
			 
			 --update #client
			 -- set open_price = b.open_price
			 -- From #market A
			 -- join #client b
			 -- on a.symbol = b.symbol;
			  
			  --ABERTURA fim--

			--MAXIMO inicio--
	drop table if exists #tb_quote_band_aid_max;
		   select 
		 distinct symbol 
			 into #tb_quote_band_aid_max
			 From #market 
			where max_price = 0; 

	drop table if exists #max_trade_id;
		   select symbol 
				, max(price) AS max_price 
			into #max_trade_id 
			From tb_trade 
			 WHERE price >= 0
		group by symbol;

	drop table if exists #paliativo_max;
		   select
		   distinct a.symbol 
				, b.max_price 
			into #paliativo_max
			 From tb_trade A
			 join #max_trade_id B 
			   on a.symbol = b.symbol
			 join #tb_quote_band_aid_max C
			   on a.symbol = c.symbol
			  and a.symbol = b.symbol
			   WHERE a.price >= 0;			  

			  update #market
			  set max_price = b.max_price
			  From #market A
			  join #paliativo_max b
			  on a.symbol = b.symbol
			  where a.max_price = 0;
			  --MAXIMO fim--

			--MINIMO inicio--
	drop table if exists #tb_quote_band_aid_min;
		   select 
		 distinct symbol 
			 into #tb_quote_band_aid_min
			 From #market 
			where min_price = 0; 

	drop table if exists #min_trade_id_b;
		   select symbol 
				, min(price) AS min_price 
			into #min_trade_id_b 
			From tb_trade 
		   where price > 0
		group by symbol;

	drop table if exists #paliativo_min;
		     select
		   distinct a.symbol 
				  , b.min_price 
			 into #paliativo_min
			 From tb_trade A
			 join #min_trade_id_b B 
			   on a.symbol = b.symbol
			 join #tb_quote_band_aid_min C
			   on a.symbol = c.symbol
			  and a.symbol = b.symbol
			   WHERE a.price >= 0;			  

			  update #market
			  set min_price = b.min_price
			  From #market A
			  join #paliativo_min b
			  on a.symbol = b.symbol
			  where a.min_price = 0;
			  --MINIMO fim--
			  
			  update #market 
			  set market_amplitude = (max_price - min_price) 

			  drop table if exists #financial_volume;
			  select symbol , sum(price * quantity) financial_volume 
			  into #financial_volume
			  From tb_trade 
			   WHERE price >= 0 
			  group by symbol 
			 
			 update #market
			 set financial_volume = b.financial_volume
			 from #market A
			 join #financial_volume B
			 on a.symbol = b.symbol


			 drop table if exists #trade_count;
			  select symbol , count(trade_id) trade_count 
			  into #trade_count
			  From tb_trade 
			  group by symbol 
			 
			 update #market
			 set trade_count = b.trade_count
			 from #market A
			 join #trade_count B
			 on a.symbol = b.symbol
			/* Band-Aid para tb_quote FIM*/

	
		/*
			Guarda as informações do cliente, nessa etapa incluimos o negocio imediatamente anterior  ao do cliente a tabela.
		*/


		 DROP TABLE IF EXISTS #client;
				SELECT account
					 , a.symbol
					 , a.exec_type
					 , a.ord_status
					 , a.last_px price		 
					 , B.yesterday_close_price		 
					 , a.lastqty quantity --obs ultima quantidade ao inves da quantidade da ordem
					 , abs(cast((a.last_px - B.yesterday_close_price) AS DECIMAL(17,4))) AS amplitude_fechamento
					 , abs(cast((a.last_px - B.open_price) AS DECIMAL(17,4)))			   AS amplitude_abertura
					 , dateadd(hour,-3 ,book_timestamp)								   AS book_timestamp
					 , a.order_key
					 , a.trade_id
					 , c.previous_trade_id
					 , c.previous_price
					 , a.process_date
					 , B.open_price
		
				  INTO #client
			      FROM tb_order a WITH(NOLOCK)
		     LEFT JOIN #market b WITH(NOLOCK)
				    ON a.symbol = b.symbol
			 LEFT JOIN #trade_id c
					ON a.symbol   = c.symbol
				   AND a.trade_id = c.trade_id
			     WHERE exec_type = 'F'  
				 OPTION (RECOMPILE, MAXDOP 4);
	
		/*
			Média ponderada do cliente
		*/
		DROP TABLE IF exists #wtavg;--#parametros;
			   SELECT account
				    , symbol
				    , exec_type
				    , yesterday_close_price
				    , sum(cast((quantity) as bigint)) as sum_quantity
				    , sum(quantity * amplitude_fechamento) AS wtavg_close_num --numerador_media_ponderada_fechamento
					, sum(quantity * amplitude_abertura)   AS wtavg_open_num  --numerador_media_ponderada_abertura
					, process_date
				INTO #wtavg --#parametros
				FROM #client
		
			GROUP BY account
				   , symbol
				   , exec_type
				   , yesterday_close_price 
				   , process_date
				   OPTION (RECOMPILE, MAXDOP 4);

			
		/*
			Calcula a media ponderada e desvio padrão do mercado
		*/	
		DROP TABLE IF EXISTS #analytics_01;--#analitico_aux;
			  SELECT a.symbol
				   , a.price
				   , trade_time
				   , b.yesterday_close_price				AS previous_close_price --previous_price_fechamento ISNULL(LAG(a.Price, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_time), b.yesterday_close_price)
				   , b.open_price							AS previous_open_price  --previous_price_abertura ISNULL(LAG(a.Price, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_time), b.open_price)	
				   , ISNULL(LAG(a.Price, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_id), a.price)								AS previous_price --previous_price_preco_anterior 
				   , ABS(a.price -  b.yesterday_close_price) AS close_amplitude --amplitude_fechamento  ABS(a.price - ISNULL(LAG(a.Price, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_id), b.yesterday_close_price))
				   , ABS(a.price -  b.open_price)		AS open_amplitude--amplitude_abertura  , ABS(a.price - ISNULL(LAG(a.Price, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_id), b.open_price))
				   , ABS(a.price - ISNULL(LAG(a.Price, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_id), a.price))					AS previous_price_amplitude--amplitude_preco_anterior ABS(a.price - ISNULL(LAG(a.Price, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_id), a.price))
				   , a.quantity	
				   ,trade_id
				   ,process_date
			   INTO #analytics_01 --#analitico_aux
			   FROM tb_trade a WITH(NOLOCK)
		  LEFT JOIN #market  b--#mercado b 
				 ON a.symbol = b.symbol
				  WHERE a.price >= 0
				 --where  a.symbol ='XRPH11' --comentar
				 OPTION (RECOMPILE, MAXDOP 4);
		

		-----ajuste 13 08 2025
		DROP TABLE IF EXISTS #analytics_02;
			   SELECT a.symbol
					, a.price
					, previous_close_price --previous_price_fechamento
					, previous_open_price --previous_price_abertura
					, close_amplitude --amplitude_fechamento
					, open_amplitude --amplitude_abertura
					, previous_price_amplitude --amplitude_preco_anterior
					, a.quantity
					
					--13 08 2025
					--,-- a.quantity * ABS(a.close_amplitude - ISNULL(LAG(close_amplitude, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_time), b.yesterday_close_price))	  
					,cast(close_amplitude * quantity as decimal(17,4))
					AS wtavg_market_close_num--numerador_media_ponderada_market_fechamento --wtavg_close_num
					
					--, a.quantity * ABS(a.open_amplitude - ISNULL(LAG(open_amplitude, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_time), b.open_price))		
					, cast(open_amplitude * quantity as decimal(17,4))
					AS wtavg_market_open_num--numerador_media_ponderada_market_abertura
					
					--, a.quantity * ABS(a.previous_price_amplitude - ISNULL(LAG(previous_price_amplitude, 1) OVER (PARTITION BY a.symbol ORDER BY a.trade_time), a.price)) 
					, cast(previous_price_amplitude * quantity as decimal(17,4))
					AS wtavg_market_previous_price_num-- numerador_media_ponderada_market_preco_anterior
				
				INTO #analytics_02
				FROM #analytics_01 a
		   LEFT JOIN #market b 
				  ON a.symbol = b.symbol
				
			  OPTION (RECOMPILE, MAXDOP 4);
		
		DROP TABLE IF EXISTS #synthetic;--#sintetico;
			   SELECT symbol
					, SUM(cast(quantity as bigint))						   AS sum_quantity
					, SUM(wtavg_market_close_num )		   AS sum_wtavg_market_close_num --sum_numerador_media_ponderada_market_fechamento 
					, SUM(wtavg_market_open_num )		   AS sum_wtavg_market_open_num  --sum_numerador_media_ponderada_market_abertura
					, SUM(wtavg_market_previous_price_num ) AS sum_wtavg_market_previous_price_num --sum_numerador_media_ponderada_market_preco_anterior
				
				INTO #synthetic
			    FROM #analytics_02
		    GROUP BY symbol
			  OPTION (RECOMPILE, MAXDOP 4);

		
		DROP TABLE IF EXISTS #wtavg_market;--#media_ponderada_mercado;
			   SELECT b.symbol
				    ,(cast(b.sum_wtavg_market_close_num			/ b.sum_quantity as decimal(17,4))) AS wtavg_market_close--media_ponderada_mercado_fechamento
				    ,(cast(b.sum_wtavg_market_open_num			/ b.sum_quantity as decimal(17,4))) AS wtavg_market_open --media_ponderada_mercado_abertura
				    ,(cast(b.sum_wtavg_market_previous_price_num / b.sum_quantity  as decimal(17,4))) AS wtavg_market_previous_price --media_ponderada_mercado_preco_anterior
			   
			   INTO #wtavg_market --#media_ponderada_mercado
			   FROM #synthetic b
		
			 OPTION (RECOMPILE, MAXDOP 4);
		
		DROP TABLE IF EXISTS #wtstdev_market--#desvio_padrao_ponderado;
			   SELECT a.symbol
					, SQRT(SUM(cast(quantity as bigint) * POWER(close_amplitude - c.wtavg_market_close, 2)) / SUM(cast(quantity as bigint)))				   AS wtstdev_market_close --desvio_padrao_ponderado_fechamento
					, SQRT(SUM(cast(quantity as bigint) * POWER(open_amplitude - c.wtavg_market_open, 2)) / SUM(cast(quantity as bigint)))					   AS wtstdev_market_open--desvio_padrao_ponderado_abertura
					, SQRT(SUM(cast(quantity as bigint) * POWER(previous_price_amplitude - c.wtavg_market_previous_price, 2)) / SUM(cast(quantity as bigint))) AS wtstdev_market_previous_price--desvio_padrao_ponderado_preco_anterior
			     
				 INTO #wtstdev_market --#desvio_padrao_ponderado
			     FROM #analytics_02 a 
			LEFT JOIN #synthetic    b 
				   ON a.symbol = b.symbol
			LEFT JOIN #wtavg_market c 
				   ON a.symbol = c.symbol
		
			 GROUP BY a.symbol
			   OPTION (RECOMPILE, MAXDOP 4);
		
		/*
			Alertas por blocos
		*/	
		
		ALTER TABLE #wtavg ADD symbol_commod VARCHAR(30);

		UPDATE #wtavg 
		   SET symbol_commod = substring(symbol,1,3)
		 WHERE (symbol like '%WIN%' or symbol like '%WDO%')
		
		UPDATE #wtavg 
		   SET symbol_commod = '-'
		 WHERE symbol_commod is null
		---------------------------------
		----------------------------CLOSE
		
		DROP TABLE IF EXISTS #close; --#fechamento
			   SELECT 
			 DISTINCT b.account,b.symbol
					, b.sum_quantity
					, b.wtavg_close_num --b.numerador_media_ponderada_fechamento
					, CAST((b.wtavg_close_num /  b.sum_quantity)AS DECIMAL(17,4))  wtavg_close--media_poderada_fechamento
					, c.market_amplitude--c.amplitude_mercado  
					, c.intraday 
					, c.interday
					, d.wtavg_market_close --media_ponderada_mercado_fechamento 
					, e.wtstdev_market_close--desvio_padrao_ponderado_fechamento
					, c.financial_volume
					, c.trade_count
					, process_date
			    INTO #close --#fechamento
			    FROM #wtavg b--#parametros b 
		   LEFT JOIN #market c--#mercado c
				  ON b.symbol = c.symbol
		   LEFT JOIN #wtavg_market d--#media_ponderada_mercado d
				  ON b.symbol = d.symbol
		   LEFT JOIN #wtstdev_market e--#desvio_padrao_ponderado e 
				  ON b.symbol = e.symbol
		
		       WHERE CAST((b.wtavg_close_num /  b.sum_quantity)AS DECIMAL(17,4)) > ((d.wtavg_market_close + (3 * wtstdev_market_close)) + 0.05)
			     AND b.symbol_commod not in ('WIN','WDO')
				OPTION (RECOMPILE, MAXDOP 4);
	
		---------------------------------
		----------------------------CLOSE
		
		---------------------------------
		-----------------------------OPEN


		DROP TABLE IF EXISTS #open--#abertura;
			   SELECT
			 DISTINCT b.account,b.symbol
					, b.sum_quantity
					, b.wtavg_open_num
					, cast((b.wtavg_open_num /  b.sum_quantity)as decimal(17,4))  wtavg_open
					, c.market_amplitude  
					, c.intraday 
					, c.interday
					, d.wtavg_market_open
					, e.wtstdev_market_open
					, c.financial_volume
					, c.trade_count
					, process_date
				INTO #open
			    FROM #wtavg b 
		   LEFT JOIN #market c
				  ON b.symbol = c.symbol
		   LEFT JOIN #wtavg_market d
				  ON b.symbol = d.symbol
		   LEFT JOIN #wtstdev_market e 
				  ON b.symbol = e.symbol
			   WHERE   cast((b.wtavg_open_num / b.sum_quantity)AS DECIMAL(17,4)) > ((d.wtavg_market_open + (3 * wtstdev_market_open)) + 0.05)
			    AND b.symbol_commod not in ('WIN','WDO')
			  OPTION (RECOMPILE, MAXDOP 4);

		---------------------------------
		-----------------------------OPEN
		
		---------------------------------
		-------------------PREVIOUS PRICE
		DROP TABLE IF EXISTS #previous_price_01; --#preco_anterior
			   SELECT account
					, symbol
					, exec_type
					, price
					, yesterday_close_price
					, quantity
					, book_timestamp
					, order_key
					, previous_price
					, previous_trade_id
					, trade_id
					, process_date
				 INTO #previous_price_01
				 FROM #client;
				
		DROP TABLE IF EXISTS #previous_price_02;--#preco_anterior_2;
			   SELECT  account
				    , symbol
				    , exec_type
				    , price
				    , previous_price
				    , ABS(price - previous_price) previous_price_amplitude --amplitude_preco_anterior
				    , yesterday_close_price
				    , quantity
				    , book_timestamp
				    , order_key 
					, process_date
			    INTO #previous_price_02
			    FROM #previous_price_01 

			   WHERE previous_price IS NOT NULL
			    OPTION (RECOMPILE, MAXDOP 4);

		DROP TABLE IF EXISTS #previous_price_03; --#preco_anterior_3;
			   SELECT account
					, symbol
					, sum(cast((quantity) as bigint)) as sum_quantity
					, SUM(quantity * previous_price_amplitude)as sum_wtavg_previous_price_num --sum_numerador_media_ponderada_preco_anterior
					, process_date
				 INTO #previous_price_03
				 FROM #previous_price_02 
		     GROUP BY account
					, symbol
					, process_date
					 OPTION (RECOMPILE, MAXDOP 4);
					 
		DROP TABLE IF EXISTS #previous_price;--#ALERTA_PRECO_ANTERIOR;
		        select b.account,b.symbol
					 , b.sum_quantity
					 , b.sum_wtavg_previous_price_num
					 , cast((b.sum_wtavg_previous_price_num /  b.sum_quantity)as decimal(17,4))  wtavg_previous_price --media_poderada_preco_anterior
					 , c.market_amplitude--amplitude_mercado  
					 , c.intraday 
					 , c.interday
					 , d.wtavg_market_previous_price --media_ponderada_mercado_preco_anterior
					 , e.wtstdev_market_previous_price --desvio_padrao_ponderado_preco_anterior
					 , c.financial_volume
					 , c.trade_count
					 , process_date
				INTO #previous_price --#alerta_preco_anterior
			    FROM #previous_price_03 b
		   LEFT JOIN #market c
				  ON b.symbol = c.symbol
		   LEFT JOIN #wtavg_market d
				  ON b.symbol = d.symbol
		   LEFT JOIN #wtstdev_market e 
				  ON b.symbol = e.symbol
			   WHERE CAST((b.sum_wtavg_previous_price_num / b.sum_quantity) AS DECIMAL(17,4)) > ((d.wtavg_market_previous_price + (3 * wtstdev_market_previous_price)) + 0.05 )
			  OPTION (RECOMPILE, MAXDOP 4);
	
		---------------------------------
		-------------------PREVIOUS PRICE
		
		
		---------------------------------
		----------------------------PRICE
		
		DECLARE @account INT,
			    @symbol  VARCHAR(30),
				@order_key BIGINT,
				@book_timestamp DATETIME2,
				@wtavg_price DECIMAL(17,4),--@media_poderada_preco DECIMAL(17,4),
				@wtstdev_price DECIMAL(17,4),--@desvio_poderada_preco DECIMAL(17,4)
				@process_date date
		
				DROP TABLE IF exists #price_01;
				CREATE TABLE #price_01 (account int,symbol varchar(30),order_key bigint,book_timestamp datetime2,wtavg_price decimal(17,4),wtstdev_price decimal(17,4),process_date date)
		
		
		DECLARE cursor_amplitude CURSOR FOR
		
			 SELECT account
				  , symbol
				  , order_key
				  , book_timestamp
				  , process_date
			   FROM #client
		   ORDER BY symbol 
				  , order_key;
		
		OPEN cursor_amplitude;
		FETCH NEXT FROM cursor_amplitude INTO @account,@symbol,@order_key,@book_timestamp,@process_date;
		
		WHILE @@FETCH_STATUS = 0
		BEGIN
		   
		   PRINT 'Account: ' + CAST(@account AS NVARCHAR(20)) +
		         ', Symbol: ' + @symbol +
		         ', Order Key: ' + CAST(@order_key AS NVARCHAR(20)) +
		         ', Book Timestamp: ' + CAST(@book_timestamp AS NVARCHAR(20));
		DECLARE @up_15 TIME = CONVERT(TIME, DATEADD(MINUTE,15, @book_timestamp))
		      , @down_15 TIME = CONVERT(TIME,DATEADD(MINUTE,-15, @book_timestamp))

			  SELECT @wtavg_price = SUM(price * quantity) / SUM(quantity) 
			    FROM tb_trade  WITH(NOLOCK)
			   WHERE symbol = @symbol 
			     AND trade_time BETWEEN @down_15 AND @up_15
			  OPTION (RECOMPILE, MAXDOP 4);

			  SELECT @wtstdev_price = SQRT(SUM(quantity * POWER(price - @wtavg_price, 2)) / SUM(quantity))
			    FROM tb_trade WITH(NOLOCK)
			   WHERE symbol = @symbol 
			     AND trade_time BETWEEN @down_15 AND @up_15
			  OPTION (RECOMPILE, MAXDOP 4);	 	
		
		 INSERT INTO #price_01 (account,symbol,order_key,book_timestamp,wtavg_price,wtstdev_price,process_date)
		      SELECT @account		 AS account
				   , @symbol		 AS symbol
				   , @order_key		 AS order_key
				   , @book_timestamp AS book_timestamp
				   , @wtavg_price    AS wtavg_price
				   , @wtstdev_price  AS wtstdev_price
				   , @process_date   AS process_date;
		
		    FETCH NEXT FROM cursor_amplitude INTO  @account,@symbol,@order_key,@book_timestamp,@process_date;
		END;
		
		CLOSE cursor_amplitude;
		DEALLOCATE cursor_amplitude;
	
		--preço maior do que 5 centavos 
		DROP TABLE IF EXISTS #price;
			  SELECT A.* 
				   , b.wtavg_price 
				   , b.wtstdev_price 
				INTO #price
			    FROM #client A
		   LEFT JOIN #price_01 b
			      ON A.order_key = b.order_key
			   WHERE price > ((wtavg_price + (3 * wtstdev_price)) + 0.05)
			  OPTION (RECOMPILE, MAXDOP 4);
			 

		 /* Bloco onde é calculado a variação */			  
		 DROP TABLE IF EXISTS #wtavg_client_buy;
				SELECT  SUM(cast(last_px * lastqty as float)) / SUM(cast((lastqty) as bigint)) AS wtavg_client_buy 
					 , account 
					 , symbol
				  INTO #wtavg_client_buy
				  FROM tb_order 
				 WHERE exec_type = 'F'
				   AND side = 1
			  GROUP BY  account 
					 , symbol
		
		 DROP TABLE IF EXISTS #wtavg_client_sell;		 
				SELECT  SUM(cast(last_px * lastqty as float))  /  SUM(cast((lastqty) as bigint))  AS wtavg_client_sell
					 , account 
					 , symbol
				  INTO #wtavg_client_sell
				  FROM tb_order 
				 WHERE exec_type = 'F'
				   AND side = 2
			  GROUP BY account 
					 , symbol

  DROP TABLE IF EXISTS #wtavg_client;
			    SELECT account
					 , symbol 
				  INTO #wtavg_client
				  FROM #wtavg_client_BUY

			    UNION

			    SELECT account
					 , symbol 
				  FROM #wtavg_client_sell 

		 DROP TABLE IF EXISTS #variation_client;
				SELECT A.account
					 , A.symbol 
					 , B.wtavg_client_buy 
					 , C.wtavg_client_sell
					, CASE WHEN (B.wtavg_client_buy is null or  C.wtavg_client_sell is null) THEN 0 ELSE ABS(B.wtavg_client_buy - C.wtavg_client_sell) END AS variation_client_pts
				  INTO #variation_client
				  FROM #wtavg_client a 
			 LEFT JOIN #wtavg_client_BUY B
				    ON A.account = B.account
				   AND A.symbol  = B.symbol
			 LEFT JOIN  #wtavg_client_sell C
				    ON A.account = c.account
				   AND A.symbol  = c.symbol
				 
		 DROP TABLE IF EXISTS #variation_client_result;
				SELECT a.* 
					 , b.wtavg_client_buy
					 , b.wtavg_client_sell
					 , b.variation_client_pts 
					 , abs(a.price - a.wtavg_price) variation_client_market
				  INTO #variation_client_result
				  FROM #price a
			 LEFT JOIN #variation_client b 
				    ON a.account = b.account
				   AND a.symbol = b.symbol
				
		 DROP TABLE IF EXISTS #price_result;
				SELECT *
				  INTO #price_result
				  FROM #variation_client_result
				 --WHERE variation_client_pts > variation_client_market -- filtro comentado pois no momento não será necessário

---------------------------------------------------------------

		---------------------------------
		----------------------------PRICE
		
		/*
			Sessão de tempo e trade
		*/
		
		DROP TABLE IF EXISTS #time_01 --#tempo;
			   SELECT account
					, symbol
					, exec_type 
					, ord_status
					, price
					, quantity
					, book_timestamp
					, LAG(book_timestamp, 1) OVER (PARTITION BY a.account,a.symbol ORDER BY a.order_key)  AS previous_book_timestamp
					, datediff(second, LAG(book_timestamp, 1) OVER (PARTITION BY a.account,a.symbol ORDER BY a.order_key),book_timestamp) AS gap_seconds 
					, order_key		
				 INTO #time_01
				 FROM #client a 
			   OPTION (RECOMPILE, MAXDOP 4);

		DROP TABLE IF exists #avg_market;--#mercado_media;
			   SELECT symbol
					, avg(cast(quantity as bigint))   AS avg_quantity 
				    , stdev(cast(quantity as bigint)) AS stdev_quantity
			     INTO #avg_market
			     FROM tb_trade 
				  WHERE price >= 0
			 GROUP BY symbol
			   OPTION (RECOMPILE, MAXDOP 4);
		
		DROP TABLE IF EXISTS #time_02;
			   SELECT 
					  CASE WHEN exec_type = 'F' and ord_status = '1' and gap_seconds = 0 THEN 1 
						   ELSE 0 
						   END  AS flag
					, a.*
			     INTO #time_02
				 FROM #time_01 a
			LEFT JOIN #avg_market b
				   ON a.symbol = b.symbol
			   OPTION (RECOMPILE, MAXDOP 4);
		
		DROP TABLE IF EXISTS #time_03;
		 	   SELECT
		     DISTINCT a.account
		 	     INTO #time_03
		 	     FROM #time_02 a
		    LEFT JOIN #avg_market b -- #mercado_media b 
		 		   ON a.symbol = b.symbol
		 	    WHERE flag = 0
			   OPTION (RECOMPILE, MAXDOP 4);
		
		/*
			Gerando resultado em blocos em um só
		*/

		DROP TABLE IF EXISTS #alert ;
		       SELECT a.account
		   	        , a.symbol
		   	        , 'OPEN' alert_type
		   	        , null price
		   	        , cast(wtavg_open AS DECIMAL(17,4))			 AS client_weighted_avg
		   	        , cast(wtavg_market_open AS DECIMAL(17,4))	 AS market_weighted_avg
		   	        , cast(wtstdev_market_open AS DECIMAL(17,4)) AS market_weighted_stdev
		   		    , a.financial_volume
		   		    , a.trade_count
					, process_date
					, null variation_client_pts
					, null variation_client_market
		   		 INTO #alert
		     	 FROM #open a
		   INNER JOIN #time_03 b
		     	   ON a.account = b.account
		
			    UNION ALL
		
			   SELECT a.account
				    , a.symbol
				    , 'CLOSE' alert_type
				    , null price
				    , cast(wtavg_close AS DECIMAL(17,4))
				    , cast(wtavg_market_close AS DECIMAL(17,4))
				    , cast(wtstdev_market_close AS DECIMAL(17,4)) 
				    , a.financial_volume
				    , a.trade_count
					, process_date
					, null variation_client_pts
					, null variation_client_market
				 FROM #close a
		   INNER JOIN #time_03 b
				   ON a.account = b.account 
		
			    UNION ALL
		
		   	   SELECT a.account
		   	        , a.symbol
		   	        , 'PRICE' alert_type
		   	        , price 
		   	        , null
		   	        , cast(wtavg_price AS DECIMAL(17,4))
		   	        , cast(wtstdev_price AS DECIMAL(17,4))
		   		    , null financial_volume
		   		    , null trade_count
					, process_date
					, a.variation_client_pts
					, a.variation_client_market
		   	     FROM #price_result a  --#PRICE
		   INNER JOIN #time_03 b
		   		   ON a.account = b.account
		
			    UNION all
		
			   SELECT a.account
					, a.symbol
					,'PREVIOUS PRICE' alert_type
					, null price 
					, CAST(wtavg_previous_price AS DECIMAL(17,4))			AS client_weighted_avg
					, CAST(wtavg_market_previous_price  AS DECIMAL(17,4))	AS market_weighted_avg
					, CAST(wtstdev_market_previous_price AS DECIMAL(17,4))  AS market_weighted_stdev
					, a.financial_volume
					, a.trade_count
					, process_date
					, null ,null
				 FROM #previous_price a
		   INNER JOIN #time_03 b
				   ON a.account = b.account;
		

		/*
			Gera o indicador de liquidez
		*/
				DROP TABLE IF EXISTS #liq_metrics;
				SELECT symbol 
					 , financial_volume
					 , trade_count  
					 , POWER(trade_count / 1000.00, 3) / (POWER(NULLIF(financial_volume, 0), 0.01) * 1000)  AS ratio
					 , symbol_timestamp 
				 INTO #liq_metrics
				 FROM #market;		

          
		  DROP TABLE IF EXISTS #metrics_osc_hist;
				SELECT a.account
					 , a.symbol
					 , a.alert_type
					 , a.price
					 , CAST(a.client_weighted_avg AS DECIMAL(17,2)) client_weighted_avg
					 , a.market_weighted_avg
					 , a.market_weighted_stdev
					 , process_date
					 , a.variation_client_pts
					 , a.variation_client_market
				  INTO #metrics_osc_hist
				  FROM #alert a 
			 LEFT JOIN #liq_metrics b
				    ON a.symbol = b.symbol	
				 WHERE a.market_weighted_stdev > 0
				 -- CAST(a.client_weighted_avg AS DECIMAL(17,2)) >= b.ratio -- Filtro comentado pois no momento não será necessário

		
				 UNION 

				SELECT a.account
					 , a.symbol
					 , a.alert_type
					 , a.price
					 , CAST(A.client_weighted_avg AS decimal(17,2)) client_weighted_avg
					 , a.market_weighted_avg
					 , a.market_weighted_stdev 
					 , process_date
					 , a.variation_client_pts
					, a.variation_client_market
				  FROM #alert a
				 WHERE alert_type = 'price'
				 and a.market_weighted_stdev > 0;


			
/* teste proporção */

            drop table if exists #pre_prop_client;
			SELECT	   account
					   ,symbol
				      ,process_date
            into #pre_prop_client
			from #metrics_osc_hist
			group by 
		    account
			,symbol
		   ,process_date



			drop table if exists #prop_client;
			SELECT  a.account
				  , a.symbol
				  , c.financial_volume market_volume
				  , sum(a.last_px * a.lastqty) client_volume
				  , avg(a.last_px * a.lastqty) / nullif(c.financial_volume,0) as prop_client
				 into #prop_client
		       FROM tb_order a WITH(NOLOCK)
		       INNER JOIN #pre_prop_client b 
		    	 ON a.account	  = b.account 
		    	AND a.process_date = b.process_date 
		    	AND a.symbol		  = b.symbol
				left join #liq_metrics c
				on a.symbol = c.symbol
		      WHERE a.exec_type = 'F' 
			  
			  group by a.account
				  , a.symbol
				  ,c.financial_volume 

	

		----terminar
		--- criar uma média de volume dos cliente por ativo ai dividir pelo volume do mercado ai se a proporção do cliente for maior que essa media é alertado.
		-- olhar os prints do novo parametro
	
		drop table if exists #prop_market
		select a.symbol , avg(quantity * price)  /  nullif(b.financial_volume,0) prop_avg_market
	     into #prop_market
		  from #market b 
		inner join tb_trade  a 
		on a.symbol = b.symbol
		 WHERE a.price >= 0
		
		group by a.symbol , b.financial_volume


		--+ (stdev(quantity * price))

		drop table if exists #prop
		select a.symbol,a.account,a.prop_client,b.prop_avg_market 
		into #prop
		From  #prop_client a 
		inner join #prop_market b 
		on a.symbol = b.symbol
		where a.prop_client >= b.prop_avg_market
		and a.prop_client > 0.05 
	
		delete
		  from #metrics_osc_hist 
		 where  not exists (select 1 from #prop a where a.account = #metrics_osc_hist.account and a.symbol = #metrics_osc_hist.symbol)
		
/*teste proporção*/


		DROP TABLE IF EXISTS  #account_osc ;
 			   SELECT 
			 DISTINCT  account
					 , symbol
					 , process_date 
				  INTO #account_osc
				  FROM #metrics_osc_hist;


 		--tb_line_chart_osc_hist 
		insert into tb_line_chart_osc_hist (symbol,resampled_time,close_amplitude,open_amplitude,previous_price_amplitude,price,process_date)
		select  a.symbol
					 ,CAST(DATEADD(MINUTE, DATEDIFF(MINUTE, 0, trade_time), 0) AS TIME) AS resampled_time
					 -- , trade_id
					  , avg(a.close_amplitude) as close_amplitude
					  , avg(a.open_amplitude ) as open_amplitude
					  , avg(a.previous_price_amplitude) as previous_price_amplitude
					  , avg(a.price) as price
					  , a.process_date
			from #analytics_01  A 
			join #account_osc B
			on a.symbol = b.symbol
			and a.process_date = b.process_date
		   GROUP BY a.symbol,
			CAST(DATEADD(MINUTE, DATEDIFF(MINUTE, 0, trade_time), 0) AS TIME)
			,a.process_date
/** 
 * Verifica Recorrência
 */

DROP TABLE IF EXISTS #recorrencia;
	  DECLARE @process_date2 DATE = (SELECT max(process_date) FROM tb_entrypoint)
	   SELECT 
	 DISTINCT account
			, process_date 
		 INTO #recorrencia
		 FROM tb_account_osc_hist 
		WHERE process_date >= dateadd(day,-180, @process_date2) 
		  AND process_date < @process_date2;	
		  

		   --tb_symbol_osc_hist
		  INSERT INTO tb_symbol_osc_hist(symbol,financial_volume,trade_count,ratio,process_date)
				SELECT symbol 
					 , financial_volume
					 , trade_count  
					 , ratio
					 , symbol_timestamp 
				  FROM #liq_metrics; 
			
		   --tb_account_osc_hist
		 INSERT INTO tb_account_osc_hist (account,symbol,process_date)
			  SELECT DISTINCT account
					 , symbol
					 , process_date 
				  FROM #metrics_osc_hist;




		DROP TABLE IF EXISTS #issue;
			   SELECT 
			 DISTINCT account
					 , symbol
					 , process_date 
				 INTO #issue
				 FROM #metrics_osc_hist;

		   --tb_metrics_osc_hist  select  *from tb_metrics_osc_hist
		  INSERT INTO tb_metrics_osc_hist (account,symbol,alert_type,price,client_weighted_avg,market_weighted_avg,market_weighted_stdev,process_date,variation_client_pts,variation_client_market,prop_client,prop_avg_market)
				SELECT a.account
					 , a.symbol
					 , a.alert_type
					 , a.price
					 , a.client_weighted_avg
					 , a.market_weighted_avg
					 , a.market_weighted_stdev
					 , a.process_date 
					 , a.variation_client_pts
					 , a.variation_client_market
					 , b.prop_client
					 , b.prop_avg_market
				  FROM #metrics_osc_hist a
				  left join #prop b 
				  on a.symbol = b.symbol 
				  and a.account = b.account;

	
		-- tb_order_osc_hist 
		INSERT INTO tb_order_osc_hist (order_key, order_id, secondary_order_id, account, order_timestamp, msg_type, party_id, price, last_px, quantity, cumqty, lastqty, leavesqty, side, symbol, exec_type, ord_status, process_date, book_timestamp, book_spread, order_spread, trade_aggressor, trade_buying_broker, trade_id, trade_price, trade_selling_broker, trade_time, trade_type,flag_cross,flag_recurrence)
			 SELECT
		   DISTINCT a.order_key
		    	  , a.order_id
		    	  , a.secondary_order_id
		    	  , a.account
		    	  , a.order_timestamp
		    	  , a.msg_type
		    	  , a.party_id
		    	  , a.price
		    	  , a.last_px
		    	  , a.quantity
		    	  , a.cumqty
		    	  , a.lastqty
		    	  , a.leavesqty
		    	  , a.side
		    	  , a.symbol
		    	  , a.exec_type
		    	  , a.ord_status
		    	  , a.process_date
		    	  , a.book_timestamp
		    	  , a.book_spread
		    	  , a.order_spread
		    	  , c.aggressor trade_aggressor
		    	  , c.broker_buy trade_buying_broker
		    	  , c.trade_id
		    	  , c.price trade_price
		    	  , c.broker_sell trade_selling_broker
		    	  , c.trade_time
		    	  , c.direct trade_type 
				  , case when c.direct = 1 then 1 else 0 end flag_cross
				  , case when d.account is not null then 1 else 0 end AS flag_recurrence
		       FROM tb_order a WITH(NOLOCK)
		 INNER JOIN #metrics_osc_hist b
		    	 ON a.account	  = b.account 
		    	AND a.process_date = b.process_date 
		    	AND a.symbol		  = b.symbol
		 LEFT JOIN tb_trade c
				 ON a.trade_id = c.trade_id
			    AND a.symbol = c.symbol
			    AND a.process_date = c.process_date 
		  LEFT JOIN #recorrencia D
				 ON a.account = d.account
		      WHERE a.exec_type = 'F';

			  insert into issues (account,date,alert_name,symbol,party_id,created_by,[rule],risk,[open],cvm_notification_date,bsm_notification_date,coaf_notification_date,adm_notification_date)
					SELECT 
						account,
						process_date,
						'Oscilação de Preços' AS alert_name,
						symbol,
						(SELECT MAX(party_id) FROM tb_party_id) AS party_id,
						'Admin' AS create_by,
						'Art. 1º e Art. 2º, II' AS [rule],
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
		 , status_description = 'Error: ' + ERROR_MESSAGE()
     WHERE id_log = @LogID;

	 RAISERROR(@ERROR_MSG, 16, 1)
END CATCH;