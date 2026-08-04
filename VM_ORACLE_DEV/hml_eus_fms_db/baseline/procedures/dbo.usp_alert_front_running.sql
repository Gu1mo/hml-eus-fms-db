CREATE PROC [dbo].[usp_alert_front_running]
AS
/*
25/07/2024 - Author: Guimo
- Linha 728, estava agrupando por resultado o que acabou duplicando dados comentei a coluna resultado do group by e ajustou
-- ajuste no join da linha 918

26/07/2024 - Author: Guimo
-- Ajuste no insert das ofertas expressivas, onde o erro ocasionava linhas a mais que nÃ£o fazem parte da analise.

14/08/2024 authot - Guimo
-- inclusÃ£o da condiÃ§Ã£o da linha 569, onde as linhas do lado B precisam sempre ser apÃ³s as linhas do lado A
15/08/2024 author - Guimo
-- inclusÃ£o da condiÃ§Ã£o no cusor do ladoB para sempre pegar as negociaÃ§Ãµes apÃ³s as ofertas expressivas, antes pegava apÃ³s o lado oposto.
12/09/2024 author - Guimotrade
--Coluna expresive_price na tabela tb_expressive_fr_hist

02/12/2024 author - Guimo
 Ajueste para o resultado do lado oposto de miniindice e minidolar.
 case when (symbol like '%WIN%' or symbol like '%WDO%' or symbol like '%BIT%') then sum(lastqty * last_px) / sum(lastqty) else sum(lastqty * last_px) end resultado_B,

05/12/2024 author - Guimo e Gobbo	 
Ajuste no resultado do lado A, retirada da multiplicaÃ§Ã£o.
Ajuste na forma que pegamos a mÃ©dia dos 10 em 10 minutos para pegar no intervalo correto.

12/12/2024 author - Guimo e Gobbo
Ajuste da coluna do resultado B e acrescentamos a coluna de quantidade minima para realizar o resultado final.

04/04/2025 - Guimo
AlteraÃ§Ã£o em todas as colunas quantidade de INT pra bigint

12/05/2025 - Guimo e Gobbo
INclusÃ£o do filtro da media da oscilaÃ§Ã£o usando tb_quote, inclusÃ£o das colunas min_quantitiy e result

18/06/2025 - Guimo e Gobbo

Ajustes para utilizar o benchmark da bsm criando o filtro agora utilizando: maior_mediana_qtd_ofertas + maior_desvio_qtd_ofertas ao inves  (menor_media_qtd_ofertas  +  menor_desvio_qtd_ofertas) * 200.
adicionamos na tb_order_fr_hist as flag de direto intencional (cross) e recorrencia.

25/07/2025 - Guimo e Gobbo

Ajuste na coluna quantidade minima, passamos a utilziar o benchmark para o intervalo negÃ³cios.

29/08/2025 - Guimo e Gobbo

InclusÃ£o da coluna de negocio direto do lado oposto

08/09/2025 - Guimo e Gobbo
Ajuste do intervalo negocios entre oferta expressiva

12/09/2025 - Guimo e Gobbo
negocios com menos de 100 de quantidade sÃ£o excluidos

15/09/2025 - Guimo e Gobbo
Ajuste id_neg e media

26/09/2025 - Guimo
Trade_id_text ajuste para exitar de erro que estourava o tamanho da coluna.

03/10/2025 - Guimo | 08/10/2025 - Guimo e Gobbo
AlteraÃ§Ã£o para eliminar cursor para melhorar performance
InclusÃ£o do delete para retirar contas que sÃ£o iguais as contas do lado expressivo.

24/10/2025 - Guimo e Gobbo
alteraÃ§Ã£o para mini incide utilizar a coluna maior_media_qtd_ofertas, fechando um pouco mais o filtro para conseguir rodar o alerta.

26/12/2025 - Guimo
Ajuste na lÃ³gica de recorrÃªncia: o JOIN foi alterado para filtrar apenas por 'account', removendo restriÃ§Ãµes de data e ativo para validar corretamente a janela de 6 meses.

13/01/2026 - Teixeira
Melhoria de performance mudando as CTEÂ´s A, AB e Masked para tabelas temporÃ¡rias. 

02/02/2026 - Guimo e Gobbinaldo
Troca a tb_quote e utilizar a tb_trade para utilizar as informaÃ§Ãµes abertura, fechamento, min , max e avg.

19/03/2026 - Guimo (solicitado por gobbo)
Trocar o nome da abertura de ocorrencia de FIRA para Admin.

17/06/2026 - Fix: Removido COMMIT/ROLLBACK pois a SP nao abre transacao propria.
              O driver ODBC gerencia a transacao externa; COMMIT aqui causava erro 266 (@@TRANCOUNT 1->0).
*/

DECLARE @LogID INT;				
DECLARE @log_process_date DATE = (SELECT max(process_date) FROM tb_entrypoint);

BEGIN TRY

    INSERT INTO log_ms (process, dt_exec, dt_begin,status_description,process_date)
    VALUES ('Front Running', GETDATE(), GETDATE(), 'Started',@log_process_date);
    SET @LogID = SCOPE_IDENTITY();

	IF (SELECT COUNT(1) FROM log_ms WHERE process = 'Front Running' AND process_date = @log_process_date) > 0
	BEGIN
	
		PRINT 'reprocessing...'

		DELETE FROM tb_order_fr_hist		WHERE process_date = @log_process_date		
		DELETE FROM tb_expressive_fr_hist	WHERE process_date = @log_process_date	
		DELETE FROM tb_line_chart_fr_hist	WHERE process_date = @log_process_date	
		DELETE FROM tb_opposite_fr_hist		WHERE process_date = @log_process_date
		DELETE FROM tb_account_fr_hist		WHERE process_date = @log_process_date
		DELETE FROM issues					WHERE alert_name = 'Front Running' and date = @log_process_date
	
	END
	ELSE
	BEGIN
		PRINT 'processing...'
	END

	--------------------------------------------------------------------
	--------------------------------------------------------------------

	DROP TABLE IF EXISTS #close_trade_id;
		  SELECT symbol 
			   , MAX(trade_id) AS close_trade_id 
			   , process_date 
		    INTO #close_trade_id 
		    FROM tb_trade 
		GROUP BY process_date
			   , symbol;
	
	DROP TABLE IF EXISTS #quote_aux; 
		   SELECT a.symbol
			    , ISNULL(CAST(MAX(CASE WHEN trade_id = 10 THEN price END) AS DECIMAL(17,2)),MAX(c.open_price))	AS open_price
			    , CAST(MIN(price)AS DECIMAL(17,4))															AS min_price
			    , CAST(MAX(price)AS DECIMAL(17,4))															AS max_price 
			    , CAST(AVG(price)AS DECIMAL(17,4))															AS avg_price
			    , CAST(MAX(CASE WHEN trade_id = b.close_trade_id THEN price END) AS DECIMAL(17,2))			AS close_price
			    , a.process_date																			AS symbol_timestamp
			INTO #quote_aux
		    FROM tb_trade  A
		    JOIN #close_trade_id B
		      ON a.symbol = b.symbol
		     AND a.process_date = b.process_date
	   LEFT JOIN tb_quote C
			  ON a.process_date = c.symbol_timestamp
			 AND a.symbol = c.symbol
		GROUP BY a.symbol 
			   , a.process_date;

	DROP TABLE IF EXISTS #quote;
		   SELECT symbol 
			    , ABS(open_price  - avg_price) AS osc_open_price
			    , ABS(min_price   - avg_price) AS osc_min_price
			    , ABS(max_price   - avg_price) AS osc_max_price
			    , ABS(close_price - avg_price) AS osc_close_price
			    , symbol_timestamp			   AS process_date
		     INTO #quote
		     FROM #quote_aux; 


drop table if exists #osc_price;
	select symbol 
		 , process_date 
		 , avg(osc_price) avg_osc_price
		 
		 into #osc_price
	 From (
	  select symbol , osc_open_price AS  osc_price , process_date
	  From #quote 
	  
		union all

	  select symbol , osc_min_price , process_date
	  From #quote 

		union all

	  select symbol , osc_max_price , process_date
	  From #quote 

		union all

	  select symbol , osc_close_price , process_date
	  From #quote
	  ) X
	  group by symbol, process_date


-------------------------------------------
	DROP TABLE IF EXISTS #entrypoint;
	
	SELECT  
	    a.order_id,
	    a.secondary_order_id,
	    a.account,
	    a.symbol,
	    a.trade_id,
	    a.side,
	    CONVERT(time, DATEADD(hour, -3, b.order_timestamp), 4) AS order_timestamp_new,
	    CONVERT(time, DATEADD(hour, -3, a.order_timestamp), 4) AS order_timestamp_trade,
	    cast(a.quantity as bigint) quantity,
	    cast(a.cumqty as bigint) cumqty,
	    cast(a.lastqty as bigint) as lastqty, -- Quantidade (por exemplo, aÃ§Ãµes) comprada/vendida neste (Ãºltimo) preenchimento.
	    a.price,
	    a.last_px, -- PreÃ§o deste (Ãºltimo) preenchimento.
	    a.trading_session_sub_id,
	    a.process_date	
	INTO 
	  #entrypoint
	FROM 
	    tb_entrypoint a 
	INNER JOIN 
	    tb_entrypoint b 
	    ON a.order_id = b.order_id
	    AND a.secondary_order_id = b.secondary_order_id
	WHERE 
	    a.exec_type = 'F'
	    AND b.exec_type = '0';
   
	CREATE NONCLUSTERED INDEX  [id004_#entrypoint] ON [dbo].[#entrypoint] ([symbol])
	INCLUDE ([order_id],[secondary_order_id],[account],[trade_id],[side],[order_timestamp_new],[order_timestamp_trade],[lastqty],[last_px],[process_date])

	
	-----------------------------------------------------------
		
	/* line_type  descriÃ§Ã£o
		 1			MÃ©dia 10 em 10 (usada para ser a linha de mÃ©dia)
		 2			MÃ©dia 1 em 1  (usada para demonstrar a linha do grafico do mercado)
	*/
	DROP TABLE IF EXISTS #linha_grafico;
	SELECT
	    a.symbol,
	    CAST(DATEADD(MINUTE, DATEDIFF(MINUTE, 0, trade_time) / 10 * 10, 0) AS TIME) AS resampled_time,
	    AVG(a.quantity)                                                               AS avg_quantity,
		stdev(a.quantity)                                                               AS stdev_quantity,
	    --MAX(a.quantity)                                                               AS max_quantity,
	    --MIN(a.quantity)                                                               AS min_quantity,
		1 as line_type,
	    a.process_date
	INTO
		#linha_grafico
	FROM
	    tb_trade a 
	WHERE EXISTS (SELECT 1 FROM 
					#entrypoint b
		WHERE a.symbol = b.symbol)
	GROUP BY
	    a.symbol,
	    CAST(DATEADD(MINUTE, DATEDIFF(MINUTE, 0, trade_time) / 10 * 10, 0) AS TIME),
	    a.process_date order by 1 , 2
		OPTION (MAXDOP 4) ;
	
	-----------------------------------------------------------
	
	DROP TABLE IF EXISTS [#ladoA];
	CREATE TABLE [#ladoA] ([order_id] [bigint] NULL,[secondary_order_id] [bigint] NULL,[account] [bigint] NULL,[symbol] [varchar](30) NULL,[trade_id] [bigint] NULL,[side] [tinyint] NULL,[order_timestamp_new] [time](7) NULL,[order_timestamp_trade] [time](7) NULL,[lastqty] [bigint] NULL,[last_px] [decimal](17, 4) NULL,[expressive_quantity] [bigint] NULL,[expressive_trade_id] [bigint] NULL,[broker_buy] [bigint] NULL,[broker_sell] [bigint] NULL,process_date date,trade_time time,avg_quantity bigint, stdev_quantity bigint, price decimal(17,2),filtro decimal(17,3))
	drop table if exists #avg_linha_grafico;
	create table #avg_linha_grafico (symbol varchar(30),avg_time time,avg_quantity bigint, stdev_quantity bigint);
	
	DECLARE @starTime TIME,@endTime TIME, @avgQuantity FLOAT, @symbol_c varchar(30), @stdev_quantity FLOAT;
	
	-- Define the cursor name and its function
	DECLARE quantity_avg_cursor CURSOR FOR
		SELECT distinct resampled_time,cast(dateadd(minute,10,cast(resampled_time as datetime2)) as time) ,a.symbol
		 FROM #linha_grafico a inner join #entrypoint b on a.symbol = b.symbol 
		 WHERE line_type =1 
	 ORDER BY symbol , resampled_time ASC

	
	-- Open the cursor
	OPEN quantity_avg_cursor;
	
	-- Fetch the first row from the cursor
	FETCH NEXT FROM quantity_avg_cursor INTO @starTime ,@endTime , @symbol_c ;
	
	-- Loop through all rows
	WHILE @@FETCH_STATUS = 0
	BEGIN
		print @symbol_c
		PRINT @starTime
		PRINT @endTime
	

		SET @avgQuantity = NULL
		SET @stdev_quantity = NULL
	
		DECLARE @filtro decimal(17,3) , @maior_media_intervalo_negs int
	
		if (@symbol_c like 'WIN%')
		begin	
			print 'WIN'
			select @filtro = (maior_media_qtd_ofertas  +  menor_desvio_qtd_ofertas) * 200  --(maior_mediana_qtd_ofertas + maior_desvio_qtd_ofertas)  * 10 --+  menor_desvio_qtd_ofertas  --(maior_mediana_qtd_ofertas + maior_desvio_qtd_ofertas)
			--(menor_media_qtd_ofertas  +  menor_desvio_qtd_ofertas) * 200 --+  menor_desvio_qtd_ofertas 
			from tb_benchmark where symbol = @symbol_c 
		end

		if (@symbol_c like 'BIT%')
		begin	
			print 'BIT'
			select @filtro = (menor_media_qtd_ofertas  +  menor_desvio_qtd_ofertas) * 200 --(maior_mediana_qtd_ofertas + maior_desvio_qtd_ofertas)
			--(menor_media_qtd_ofertas  +  menor_desvio_qtd_ofertas) * 200 --+  menor_desvio_qtd_ofertas 
			from tb_benchmark where symbol = @symbol_c			
		end
		
		if  (@symbol_c like 'WDO%') 
		begin	
			print 'WDO'
			select @filtro =  (menor_media_qtd_ofertas  +  menor_desvio_qtd_ofertas) * 200--(maior_mediana_qtd_ofertas + maior_desvio_qtd_ofertas)
			--(menor_media_qtd_ofertas  +  menor_desvio_qtd_ofertas) * 200
			from tb_benchmark where symbol = @symbol_c
		end
	
		if  (@symbol_c not like 'WDO%' and @symbol_c not like 'WIN%' and @symbol_c not like 'BIT%')
		begin
			print 'else'
			select @filtro = maior_mediana_qtd_ofertas + maior_desvio_qtd_ofertas
			--menor_media_qtd_ofertas +  menor_desvio_qtd_ofertas 
			from tb_benchmark where symbol = @symbol_c
		end

		--declare @media_intervalo_teste varchar(20)
	
	select @maior_media_intervalo_negs = DATEDIFF(MILLISECOND, '00:00:00.000', maior_media_intervalo_negs)  --,  @media_intervalo_teste= maior_media_intervalo_negs
	from tb_benchmark 
	where symbol = @symbol_c
	
	print @filtro

			print @symbol_c+':' + cast(@filtro as varchar)
	
		SELECT @avgQuantity	   = AVG(quantity) 
			 , @stdev_quantity = STDEV(quantity)
		  FROM
			tb_trade
		 WHERE
			symbol = @symbol_c
		AND
			trade_time >= @starTime
		AND
			trade_time <= @endTime
	
		PRINT @avgQuantity
		PRINT @stdev_quantity 
		PRINT @avgQuantity + @stdev_quantity
	
		DROP TABLE IF EXISTS #MKT
		SELECT A.id_trade
			 , A.msg_time
			 , A.header
			 , A.symbol
			 , A.task
			 , A.price
			 , A.quantity
			 , A.trade_time
			 , DATEADD(MILLISECOND, - @maior_media_intervalo_negs, A.trade_time) trade_time_5_sec --3 --5
			 --,@media_intervalo_teste as benchmark
			 , A.broker_buy
			 , A.broker_sell
			 , A.trade_id
			 , A.direct
			 , A.aggressor
			 , A.process_date	 
			 , @avgQuantity avg_quantity
			 , @stdev_quantity stdev_quantity
			 , @avgQuantity * @stdev_quantity filter_value
			 ,CASE
	    WHEN A.symbol LIKE 'WDO%' THEN 1
	    WHEN A.symbol LIKE 'WIN%' THEN 2
	    ELSE 0
	  END flag
	  INTO #MKT
		  FROM
			tb_trade a
	
		 WHERE
			a.symbol = @symbol_c
		AND
			a.trade_time >= @starTime
		AND
			a.trade_time <= @endTime
		AND 
			a.quantity > @filtro
	
	    create index id001_#mkt on #MKT (symbol,trade_time_5_sec,trade_time,trade_id)
	
			insert into [#ladoA]
	                 SELECT
	                        a.order_id,
	                        a.secondary_order_id,
	                        account,
	                        a.symbol,
	                        a.trade_id,
	                        a.side,
	                        a.order_timestamp_new,
	                        a.order_timestamp_trade,
	                        a.lastqty,
	                        a.last_px,
	                        b.quantity expressive_quantity,
	                        b.trade_id expressive_trade_id,
	                        b.broker_buy,
	                        b.broker_sell,
	                        a.process_date,
	                        b.trade_time,
							null avg_quantity,
							null stdev_quantity,
							b.price,
							null filtro
	                    from
	                        #entrypoint    a 
	                        inner join
	                            #MKT b
	                                on a.symbol = b.symbol
	                                   --and a.order_timestamp_trade between b.trade_time_5_sec and b.trade_time  -- ajuste mudnado de timestamp_new para trade (a.order_timestamp_new)
	                                   and a.order_timestamp_trade >= b.trade_time_5_sec and a.order_timestamp_trade < b.trade_time --aqui
	                                   and a.trade_id <> b.trade_id
							WHERE A.symbol = @symbol_c
					
						insert into #avg_linha_grafico
				select @symbol_c,@starTime, @avgQuantity, @stdev_quantity
						
	    -- Fetch the next row from the cursor
	    FETCH NEXT FROM quantity_avg_cursor INTO @starTime ,@endTime , @symbol_c;
	END
	
	-- Close and deallocate the cursor
	CLOSE quantity_avg_cursor;
	DEALLOCATE quantity_avg_cursor; 
	

	print 'FIM CURSOR'

	-- remove Lado A quando a oferta expressiva pertence Ã  MESMA conta analisada
	DELETE A
	FROM #ladoA AS A
	JOIN #entrypoint AS E
	  ON E.trade_id     = A.expressive_trade_id
	 AND E.symbol       = A.symbol
	 AND E.process_date = A.process_date
	WHERE E.account = A.account;   -- <- garante â€œmesma contaâ€

	-----------------------------------------------------------
	--17 minutos
	CREATE INDEX [id001_#entrypoint] ON [#entrypoint] ([symbol] ASC, [order_timestamp_new] ASC) INCLUDE ([order_id], [secondary_order_id], [account], [trade_id], [side], [order_timestamp_trade], [lastqty], [last_px])
	CREATE INDEX [id002_#entrypoint] ON [#entrypoint] ([symbol] ASC, [order_timestamp_new] ASC, [trade_id] ASC);
	CREATE INDEX [id003_#entrypoint] ON [#entrypoint] ([account], [symbol], [trade_id], [order_timestamp_trade]) INCLUDE ([side]);
	
	-----------------------------------------------------------	   
	-- - Verificar se uma oferta com uma quantidade expressiva entrou no mercado, caso sim, procurar uma oferta da 
	 --Toro x segundos anteriores no mesmo lado (c, c) e apÃ³s isso pegar essa oferta e ver se o cara lucrou.
	-- */
	
	-----------------------------------------------------------		
	
	-----------------------------------------------------------		
	drop table if exists #distinct_lado_A;
	select distinct
	    a.order_id,
	    a.secondary_order_id,
	    account,
	    a.symbol,
	    a.trade_id,
	    a.side,
	    a.order_timestamp_new,
	    a.order_timestamp_trade,
	    a.lastqty,
	    a.last_px,
	    a.process_date,
		b.avg_quantity,
		b.stdev_quantity
	into
	#distinct_lado_A 
		
	From
	    #ladoA a
		 join #linha_grafico B
		on a.symbol = b.symbol
		and a.process_date = b.process_date
		and a.order_timestamp_trade between b.resampled_time and cast(dateadd(minute,10,cast(resampled_time as datetime2)) as time) 
		and b.line_type = 1

	-----------------------------------------------------------
	
	CREATE INDEX [id001_#distinct_lado_A] ON [#distinct_lado_A] ([account], [symbol], [trade_id], [order_timestamp_trade], [side]) INCLUDE ([order_id], [secondary_order_id], [order_timestamp_new], [lastqty], [last_px]);
	CREATE INDEX [id002_#distinct_lado_A] ON [#distinct_lado_A] ([symbol], [account], [order_timestamp_trade], [side], [trade_id]);
	
	-----------------------------------------------------------
	-----------------------------------------------------LADO B
	---pega lado oposto apÃ³s o trade
	-- Passo 1: Criar uma tabela temporÃ¡ria para armazenar o resultado do primeiro join por `symbol` e `account`
	DROP TABLE IF EXISTS #filtered_symbol_account; 
	SELECT DISTINCT
	    B.*
	INTO
	    #filtered_symbol_account
	FROM
	    #entrypoint B
	WHERE
	    EXISTS
	    (
	        SELECT
	            1
	        FROM
	            #distinct_lado_A A
	        WHERE
	            A.symbol = B.symbol
	            AND A.account = B.account
	    )
	OPTION (MAXDOP 4);
	-- Passo 2: Aplicar a condiÃ§Ã£o de `side` e armazenar em outra tabela temporÃ¡ria
	DROP TABLE IF EXISTS #filtered_side;
	SELECT
	    *
	INTO
	    #filtered_side
	FROM
	    #filtered_symbol_account B
	WHERE
	    EXISTS
	    (
	        SELECT
	            1
	        FROM
	            #distinct_lado_A A
	        WHERE
	            A.symbol = B.symbol
	            AND A.account = B.account
	            AND A.side <> B.side
	    )
	OPTION (MAXDOP 4);
	
	CREATE INDEX id001_#filtered_side
	    ON #filtered_side ([symbol], [order_timestamp_trade], [account], [trade_id], [side])
	    INCLUDE ([order_timestamp_new], [lastqty], [last_px], [order_id], [secondary_order_id])

CREATE NONCLUSTERED INDEX idx_filtered_side
ON #filtered_side (symbol, account, trade_id, order_timestamp_trade, side);

CREATE NONCLUSTERED INDEX idx_distinct_lado_a
ON #distinct_lado_A (symbol, account, trade_id, order_timestamp_trade, side);

	-- Passo 3: Aplicar as condiÃ§Ãµes de `order_timestamp_trade` e `trade_id` e armazenar o resultado final
DROP TABLE IF EXISTS #ladoB;	
	SELECT DISTINCT
    B.order_id,
    B.secondary_order_id,
    B.account,
    B.symbol,
    B.trade_id,
    B.side,
    B.order_timestamp_new,
    B.order_timestamp_trade,
    B.lastqty,
    B.last_px,
    B.process_date
	INTO
    #ladoB
FROM
    #filtered_side B
JOIN
    #distinct_lado_A A
    ON  A.symbol = B.symbol
    AND A.account = B.account
    AND B.order_timestamp_trade >= A.order_timestamp_trade
    AND B.trade_id > A.trade_id
    AND A.side <> B.side
OPTION (MAXDOP 4);


	CREATE INDEX id001_#ladoB ON [dbo].[#ladoB] ([account], [trade_id], [symbol])
	    include
	    ([order_id], [secondary_order_id], [side], [order_timestamp_new], [order_timestamp_trade], [lastqty], [last_px])
	DROP INDEX id001_#ladoB
	    ON [dbo].[#ladoB]
	

	drop table if exists [#lado_B_certo];
	CREATE TABLE [#lado_B_certo]
	    (
	        [order_id]              [bigint]         NULL,
	        [secondary_order_id]    [bigint]         NULL,
	        [account]               [bigint]         NULL,
	        [symbol]                [varchar](30)    NULL,
	        [trade_id]              [bigint]         NULL,
	        [side]                  [tinyint]        NULL,
	        [order_timestamp_new]   [time](7)        NULL,
	        [order_timestamp_trade] [time](7)        NULL,
	        [lastqty]               [bigint]            NULL,
	        [last_px]               [decimal](17, 4) NULL,
	        id_neg                  int,
	        process_date            date
	    )
	
	
	drop table if exists #lado_A_certo_aux;
	DROP TABLE IF EXISTS #lado_A_certo;
	SELECT DISTINCT order_id
		 ,secondary_order_id
		 ,account
		 ,symbol
		 ,trade_id
		 ,side
		 ,order_timestamp_new
		 ,order_timestamp_trade
		 ,lastqty
		 ,last_px
		 ,process_date
		 --,avg_quantity
		 --,stdev_quantity
	    ,DENSE_RANK() OVER (PARTITION BY
	                           account,
	                           symbol
	                       ORDER BY
	                           trade_id --aqui

	                      ) id_neg
	INTO
	    #lado_A_certo_aux
	FROM
	    #distinct_lado_A 
------
--add 17 06 2025
		drop table if exists #direto;
		select 
		 a.symbol, a.account,a.process_date , sum(case when b.direct = 1 then 1 else 0 end) flag_cross
		into #direto
		From #distinct_lado_A  a
		join tb_trade B 
		on a.trade_id = b.trade_id
		and a.process_date = b.process_date
		and a.symbol = b.symbol
		group by  a.symbol, a.account , a.process_date
------
 
   drop table if exists #lado_A_certo;
	select order_id
		 ,secondary_order_id
		 ,account
		 ,symbol
		 ,max(trade_id)trade_id
		 ,side
		 ,order_timestamp_new
		 ,max(order_timestamp_trade) max_order_timestamp_trade
		 ,SUM(cast(lastqty as bigint)) lastqty
		 ,max(last_px)last_px --sum(last_px)last_px --alterei 30 10 2024 -estava somando agora esta pegando maximo
		 ,process_date
		 --,avg_quantity
		 --,stdev_quantity
		 ,max(id_neg)id_neg
		-- ,string_agg(trade_id,',') trade_id_text
		,STRING_AGG(CAST(trade_id AS VARCHAR(MAX)), ';') 
        WITHIN GROUP (ORDER BY trade_id) AS trade_id_text
		INTO #lado_A_certo
	 From #lado_A_certo_aux    
	 group by order_id
		 ,secondary_order_id
		 ,account
		 ,symbol
		 ,side
		 ,order_timestamp_new
		 --,order_timestamp_trade
		 ,process_date
		 --,avg_quantity
		 --,stdev_quantity
	

CREATE INDEX id001_#lado_A_certo
ON #lado_A_certo (trade_id, account, symbol, id_neg);
	
CREATE NONCLUSTERED INDEX idx_ladoB
ON #ladoB (account, symbol, trade_id, side);

CREATE NONCLUSTERED INDEX idx_ladoA
ON #lado_A_certo (account, symbol, trade_id, side);


	insert into #lado_B_certo 
	        select   b.order_id,
	                b.secondary_order_id,
	                b.account,
	                b.symbol,
	                b.trade_id,
	                b.side,
	                b.order_timestamp_new,
	                b.order_timestamp_trade,
	                b.lastqty,
	                b.last_px,
	                a.id_neg,
	                b.process_date
	from #ladoB b 
	inner join #lado_A_certo a 
			on b.account = a.account 
		   and b.symbol = a.symbol
		 where b.trade_id > a.trade_id and b.side <> a.side
	OPTION (HASH JOIN, MAXDOP 4);
	


	--------------------------------------------
	drop table if exists [#lado_B_certo_2];
	CREATE TABLE [#lado_B_certo_2]
	    (
	        [order_id]              [bigint]         NULL,
	        [secondary_order_id]    [bigint]         NULL,
	        [account]               [bigint]         NULL,
	        [symbol]                [varchar](30)    NULL,
	        [trade_id]              [bigint]         NULL,
	        [side]                  [tinyint]        NULL,
	        [order_timestamp_new]   [time](7)        NULL,
	        [order_timestamp_trade] [time](7)        NULL,
	        [lastqty]               [bigint]            NULL,
	        [last_px]               [decimal](17, 4) NULL,
	        id_neg                  int,
	        process_date            date
	    )

	drop table if exists #expressive_order;
	select 
	distinct account,symbol,expressive_trade_id 
	into #expressive_order
	from [#ladoA] ;


			/* ==========================================================
			   A: normaliza Lado A e captura o "piso" expressivo (NULL se nÃ£o houver)
			   - Mantemos NULL (sem ISNULL) para reproduzir o mesmo efeito do cursor.
			   ========================================================== */
		
			drop table if exists #A;
				SELECT
					ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS a_id,   -- chave sintÃ©tica por linha de A
					a.account,
					a.symbol,
					a.side,
					a.id_neg,
					a.max_order_timestamp_trade              AS t_ref,        -- horÃ¡rio de referÃªncia do A
					CAST(a.lastqty AS BIGINT)                AS target_qty,   -- quantidade do A a ser coberta
					(
						SELECT MIN(e.expressive_trade_id)
						FROM #expressive_order e
						WHERE e.account = a.account
						  AND e.symbol  = a.symbol
					)                                         AS min_expressive_trade_id
					into #A
				FROM #lado_A_certo a
			

			/* ==========================================================
			   AB: une B elegÃ­vel a cada A (mesma conta/sÃ­mbolo/id_neg)
			   - B deve ser apÃ³s t_ref (estritamente >, igual ao cursor)
			   - EXIGE que exista expressivo e B.trade_id > min_expressive_trade_id
			   ========================================================== */
			--AB AS
			--(
			drop table if exists #AB;
				SELECT
					A.a_id,
					A.account,
					A.symbol,
					A.id_neg,
					A.t_ref,
					A.target_qty,
					A.min_expressive_trade_id,

					B.order_id,
					B.secondary_order_id,
					B.account              AS account_B,
					B.symbol               AS symbol_B,
					B.trade_id,
					B.side                 AS side_B,
					B.order_timestamp_new,
					B.order_timestamp_trade,
					B.lastqty,
					B.last_px,
					B.id_neg               AS id_neg_B,
					B.process_date
				into #AB
				FROM #A A
				JOIN #lado_B_certo B
				  ON B.account = A.account
				 AND B.symbol  = A.symbol
				 AND B.id_neg  = A.id_neg
				 AND B.order_timestamp_trade > A.t_ref                   -- igual ao cursor: estritamente depois do A
				 AND A.min_expressive_trade_id IS NOT NULL              -- igual ao cursor: se nÃ£o houver expressivo, nada entra
				 AND B.trade_id > A.min_expressive_trade_id             -- depois do primeiro trade expressivo
				-- Se quiser garantir lados opostos (o cursor nÃ£o restringe):
				-- AND B.side <> A.side
			

			/* ==========================================================
			   Marked: soma acumulada de B por A (ordem por trade_id)
			   - prev_run_qty = soma ANTES da linha
			   - run_qty      = soma ATÃ‰ a linha (incluindo)
			   ========================================================== */

			drop table if exists #Marked;
				SELECT
					AB.*,
					SUM(cast((AB.lastqty) as bigint)) OVER (
						PARTITION BY AB.a_id
						ORDER BY AB.trade_id
						ROWS UNBOUNDED PRECEDING
					) AS run_qty,

					SUM(cast((AB.lastqty) as bigint)) OVER (
						PARTITION BY AB.a_id
						ORDER BY AB.trade_id
						ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
					) AS prev_run_qty
				into #Marked
				FROM #AB AB
	

			-- ==========================================================
			-- INSERT: pega sÃ³ os B necessÃ¡rios atÃ© cobrir a meta do A
			-- Regra equivalente ao cursor: inclui a linha enquanto
			-- a soma ANTERIOR (prev_run_qty) ainda Ã© < target_qty.
			-- A linha que ultrapassa a meta tambÃ©m entra, tal como no cursor.
			-- ==========================================================
			INSERT INTO #lado_B_certo_2
					(order_id, secondary_order_id, account, symbol, trade_id, side,
					 order_timestamp_new, order_timestamp_trade, lastqty, last_px, id_neg, process_date)
			SELECT
				m.order_id,
				m.secondary_order_id,
				m.account_B,              -- mantÃ©m account do B (mesmo do A)
				m.symbol_B,
				m.trade_id,
				m.side_B,
				m.order_timestamp_new,
				m.order_timestamp_trade,
				m.lastqty,
				m.last_px,
				m.id_neg_B,
				m.process_date
			FROM #Marked m
			WHERE ISNULL(m.prev_run_qty, 0) < m.target_qty
			ORDER BY m.a_id, m.trade_id;  -- opcional: ordena inserÃ§Ã£o como no consumo sequencial

	
	--------------------------------------------

	
	drop table if exists #resultado_teste;
	
	drop table if exists #lado_B_temp;
	select
	    account,
	    symbol,
	    side,
	    id_neg,
	    sum(cast((lastqty * last_px) as float)) / sum(cast((lastqty) as float)) as resultado_B,
	    process_date
	into
	   #lado_B_temp
	from
	    #lado_B_certo_2 
	group by
	    account,
	    symbol,
	    side,
	    id_neg,
	    process_date



		drop table if exists #qtd_min; 
		select 
			   account,
			   symbol,
			   id_neg,
			   process_date,
			   min(lastqty)lastqty_min
		into #qtd_min
		From (
		select account,symbol,side,id_neg,process_date,lastqty From #lado_A_certo 
		union
		select account,symbol,side,id_neg,process_date,sum(cast((lastqty) as bigint)) lastqty From #lado_B_certo_2
		group by account,symbol,side,id_neg,process_date
		) x
		group by
			   account,
			   symbol,
			   id_neg,
			   process_date


	--------------------------------------------


	drop table if exists #temp;
	select
	    a.*,
	    a.last_px resultado_A,
	    b.resultado_B
	into
	   #temp
	from
	    #lado_A_certo    A
	    left join
	        #lado_B_temp B
	            on a.account = b.account
	               and a.symbol = b.symbol
	               and a.id_neg = b.id_neg

	----------------------------------------------------------
	drop table if exists #temp2;
	select
	    a.*,
	    CASE
	        WHEN a.side = 1
	            THEN (a.resultado_b - a.resultado_A) * b.lastqty_min
	        ELSE
	            (a.resultado_A - a.resultado_b)* b.lastqty_min
	    END resultado
	into
	    #temp2
	from
	    #temp a  
		left join #qtd_min b
		on a.symbol = b.symbol
		and a.process_date = b.process_date
		and a.id_neg = b.id_neg
		and a.account = b.account

	----------------------------------------------------------
	
	
	drop table if exists #temp_aux_2;
	select
	    a.order_id,
	    a.secondary_order_id,
	    a.account,
	    a.symbol,
	    trade_id_text as trade_id,
	    a.side,
	    max(order_timestamp_new)   order_timestamp_new,
	    max(max_order_timestamp_trade) order_timestamp_trade,
	    sum(lastqty)               lastqty,
	    max(last_px)               last_px,
	    --min(a.id_neg)              id_neg,
	    max(resultado_B)           resultado_B,
	    a.process_date,
		id_neg
	into
	   #temp_aux_2 
	From
	    #temp         a

	group by
	    a.order_id,
	    a.secondary_order_id,
		trade_id_text,
	    a.account,
	    a.symbol,
	    a.side,
	    a.process_date,
		id_neg


	drop table if exists #temp_aux_3;

	select
	    order_id,
	    secondary_order_id,
	    account,
	    symbol,
	    cast(trade_id as varchar) trade_id,
	    side,
	    order_timestamp_new,
	    max_order_timestamp_trade,
	    lastqty,
	    last_px,
	    id_neg,
		last_px    resultado_A,
	    resultado_b,
	    process_date
	into
	    #temp_aux_3 			
	From
	    #temp a
	where
	    not exists
	    (
	        select
	            1
	        from
	            #temp_aux_2 b
	        where
	            a.account = b.account
	            and a.symbol = b.symbol
	            and a.secondary_order_id = b.secondary_order_id
	            and a.order_id = b.order_id
	    ) 
	union all
	select
	    order_id,
	    secondary_order_id,
	    account,
	    symbol,
	    trade_id,
	    side,
	    order_timestamp_new,
	    order_timestamp_trade,
	    lastqty,
	    last_px,
	    id_neg,
	    --lastqty * last_px    resultado_A, --ajuste 2024-12-05
		last_px    resultado_A,
	    resultado_b,
	    process_date
	from
	    #temp_aux_2
	

	drop table if exists #temp3;
	select
	    a.*,
	    CASE
	        WHEN a.side = 1
	            THEN (cast(a.resultado_b as decimal(17,3))- a.resultado_A) * b.lastqty_min
	        ELSE
	            (a.resultado_A - cast(a.resultado_b as decimal(17,3))) * b.lastqty_min
	    END resultado ,
		CASE
	        WHEN a.side = 1
	            THEN (cast(a.resultado_b as decimal(17,3))- a.resultado_A) 
	        ELSE
	            (a.resultado_A - cast(a.resultado_b as decimal(17,3))) 
	    END net_value --inclusaop da coluna net_value
		, b.lastqty_min
	into
	    #temp3
	From
	    #temp_aux_3 a
			left join #qtd_min b
		on a.symbol = b.symbol
		and a.process_date = b.process_date
		and a.id_neg = b.id_neg
		and a.account = b.account





	select
	    A.*,b.avg_osc_price
	into
	    #resultado_teste 
	From
	    #temp3 A
		left join #osc_price B
		on a.symbol = b.symbol
		and a.process_date = b.process_date
	where

	    resultado > 0 -- era 1 
	 and abs(resultado_A - resultado_B) > avg_osc_price

	 
		insert into #linha_grafico
	SELECT
	    a.symbol,
	    CAST(DATEADD(MINUTE, DATEDIFF(MINUTE, 0, trade_time), 0) AS TIME) AS resampled_time,
	    AVG(a.quantity) AS avg_quantity,
	    stdev(a.quantity) AS stdevg_quantity,
	    --MIN(a.quantity) AS min_quantity,
		2 line_type,
	    a.process_date
	
	
	FROM
	    tb_trade a
	WHERE EXISTS (
	    SELECT 1 
	    FROM #entrypoint b
	    WHERE a.symbol = b.symbol
	) 
	GROUP BY
	    a.symbol,
	    CAST(DATEADD(MINUTE, DATEDIFF(MINUTE, 0, trade_time), 0) AS TIME),
	    a.process_date
	OPTION (MAXDOP 4);

	DROP TABLE IF EXISTS #resultado;
	SELECT t.* 
		 , i.avg_quantity
		 , i.stdev_quantity
		 , avg_time AS avg_time_begin 
		 , DATEADD(MINUTE, 10, i.avg_time)  AS avg_time_end  

	iNTO #resultado
	FROM 
		#resultado_teste t
	JOIN 
		#avg_linha_grafico i 
	ON 
		t.symbol = i.symbol
		AND t.max_order_timestamp_trade >= i.avg_time -- ComeÃ§o do intervalo
		AND t.max_order_timestamp_trade < DATEADD(MINUTE, 10, i.avg_time) -- Final do intervalo		
		AND t.lastqty > ((i.avg_quantity ) + (3 * stdev_quantity))   ;
	

		  --mantÃ©m cliente quando a oferta for antes da oferta expressiva e menor
		  drop table if exists #expresive;
		  SELECT 
		DISTINCT
				b.account,
				b.symbol,
				b.trade_id,
				a.expressive_quantity,
				a.expressive_trade_id,
				broker_buy,
				broker_sell,
				trade_time,
				a.avg_quantity,
				a.stdev_quantity,
				b.id_neg,
				b.process_date,
				a.price,
				c.lastqty,
				c.max_order_timestamp_trade
				
			
			INTO #expresive
			FROM #temp b 
	   LEFT JOIN #ladoA a
		      ON a.account = b.account
		     AND a.symbol = b.symbol
		     AND a.trade_id = b.trade_id
	  INNER JOIN #resultado c -- #resultado_teste c 
			  ON b.secondary_order_id = c.secondary_order_id
			  and b.id_neg = c.id_neg
			  where c.lastqty < a.expressive_quantity
			  and a.trade_time > c.max_order_timestamp_trade --a.trade_time < c.order_timestamp_trade a oferta expressiva tem quer sempre vir depois da oferta do cliente
			
			  delete from #resultado  where not exists (select 1 
															from #expresive b 
															where #resultado.id_neg = b.id_neg
															and #resultado.account = b.account
															and #resultado.symbol = b.symbol);

			delete from #resultado where lastqty < 100;

 DROP TABLE IF EXISTS #direto_opposite;
		select 
		   a.symbol
		 , a.trade_id
		 , a.account
		 , a.process_date 
		 , sum(case when b.direct = 1 then 1 else 0 end) AS flag_cross
	  into #direto_opposite
	  From #lado_B_certo_2  a
	  join tb_trade B 
		on a.trade_id = b.trade_id
	   and a.process_date = b.process_date
	   and a.symbol = b.symbol
	 WHERE exists (SELECT 1 
				     FROM #resultado b --#resultado_teste b 
				    WHERE a.account = b.account 
					  and a.symbol = b.symbol 
					  and a.id_neg = b.id_neg)
  GROUP BY a.symbol
		 , a.account 
		 , a.process_date 
		 , a.trade_id;
						
------
--add 17 06 2025
	DROP TABLE IF EXISTS #recorrencia;
	  DECLARE @process_date DATE = (SELECT max(process_date) FROM tb_entrypoint)
	   SELECT 
	 DISTINCT account
			--, process_date 
		 INTO #recorrencia
		 FROM tb_account_fr_hist 
		WHERE process_date >= dateadd(day,-180, @process_date) 
		  AND process_date < @process_date;						
	-------- Tabelas
	------------------------------------------------------------------

	---tb_account_fr_hist (cabeÃ§alho) 
	INSERT INTO tb_account_fr_hist (account,symbol,process_date)
		 SELECT
	   DISTINCT 
		     account,
		     symbol,
		     process_date
			
		 FROM
		 #resultado
		
		DROP TABLE IF EXISTS #issues;
		SELECT
	   DISTINCT 
		     account,
		     symbol,
		     process_date
		 INTO #issues			
		 FROM #resultado
		     --#resultado_teste 

	--tb_line_chart_fr_hist(Linha do grÃ¡fico)
	CREATE NONCLUSTERED INDEX [idx01_#linha_grafico] ON #linha_grafico ([line_type]) INCLUDE ([symbol],[resampled_time],[avg_quantity],[process_date])
	CREATE NONCLUSTERED INDEX [idx01_#avg_linha_grafico] ON #avg_linha_grafico ([symbol],[avg_time]) INCLUDE ([avg_quantity])

    INSERT INTO tb_line_chart_fr_hist(symbol,resampled_time,avg_quantity,line_type,process_date) 
	 	 SELECT a.symbol,
	 		    a.resampled_time,
	 		    b.avg_quantity,
	 		    a.line_type,
	 		    a.process_date 
	 	  FROM #linha_grafico a 
	 LEFT JOIN #avg_linha_grafico b 
	 	    ON	a.symbol = b.symbol
	 	   AND a.resampled_time = b.avg_time
	 	 WHERE line_type = 1

	 	union all
	 	select  a.symbol,
	 		   a.resampled_time,
	 		   a.avg_quantity,
	 		   a.line_type,
	 		   a.process_date  
	      from #linha_grafico a 
	 	where line_type = 2
	
	--------------------------------
	


	--tb_order_fr_hist(NegociaÃ§Ãµes) alter table tb_order_fr_hist alter column trade_id varchar(50)
	INSERT INTO tb_order_fr_hist(order_id,secondary_order_id,account,symbol	,trade_id_text,side	,order_timestamp,quantity,price,side_value,opposite_value,result,result_key,process_date,flag_recurrence, flag_cross , min_quantity,net_value) 
		 SELECT 
		     a.order_id,
		     a.secondary_order_id,
		     a.account,
		     a.symbol,
		     a.trade_id trade_id_text,
		     a.side,
		     a.max_order_timestamp_trade AS order_timestamp, --alterando para a a hora do trade antes era order_timestamp_new
		     a.lastqty               AS quantity,
		     a.last_px               AS price,
		     a.resultado_A,
		     a.resultado_B,
		     a.resultado,
			 a.id_neg,
		     a.process_date ,
			 case when b.account is not null then 1 else 0 end flag_recurrence,
			 c.flag_cross,
			 lastqty_min as min_quantity,
			 net_value as net_value
		 FROM
		     --#resultado_teste
			 #resultado a
			 left join #recorrencia b 
			 on a.account = b.account
			 --and a.process_date = b.process_date
			left join #direto c
			on a.process_date = c.process_date
			and a.symbol = c.symbol
			and a.account = c.account


	--tb_expressive_fr_hist(Ofertas expressivas) sp_help tb_expressive_fr_hist

	INSERT INTO tb_expressive_fr_hist (account,symbol,trade_id,expressive_quantity,expressive_trade_id,broker_buy,broker_sell,trade_time,avg_quantity,stdev_quantity,result_key,process_date,expressive_price)
		  SELECT 
		DISTINCT
				b.account,
				b.symbol,
				b.trade_id,
				a.expressive_quantity,
				a.expressive_trade_id,
				broker_buy,
				broker_sell,
				trade_time,
				c.avg_quantity,
				c.stdev_quantity,
				b.id_neg,
				b.process_date,
				a.price--,
				--c.lastqty,
				--c.order_timestamp_trade
			FROM #temp b 
	   LEFT JOIN #ladoA a
		      ON a.account = b.account
		     AND a.symbol = b.symbol
		     AND a.trade_id = b.trade_id
	  INNER JOIN #resultado c -- #resultado_teste c 
			  ON b.secondary_order_id = c.secondary_order_id
			  and b.id_neg = c.id_neg
			  and a.expressive_quantity > c.lastqty --aqui adicionado para sÃ³ trazer oferta expresiva maior
			  order by id_neg

--tb_opposite_fr_hist
---------------------
	INSERT INTO tb_opposite_fr_hist	(order_id,secondary_order_id,account,symbol,trade_id,side,order_timestamp,quantity,price,result_key,process_date,flag_cross)
	  	 SELECT 
	   DISTINCT a.order_id
			  , a.secondary_order_id
			  , a.account
			  , a.symbol
			  , a.trade_id
			  , a.side 
			  , a.order_timestamp_trade 
			  , a.lastqty
			  , a.last_px
			  , a.id_neg
			  , a.process_date
			  , c.flag_cross

	  	   FROM #lado_B_certo_2 a
		   left join #direto_opposite c
			on a.process_date = c.process_date
			and a.symbol = c.symbol
			and a.account = c.account
		  WHERE exists (SELECT 1 FROM #resultado b --#resultado_teste b 
								WHERE a.account = b.account and a.symbol = b.symbol and a.id_neg = b.id_neg)

--------------------------------------------------------

	drop table if exists #tb_order_fr_hist;
			SELECT 
		     lastqty               AS quantity,
			 	symbol,account,
			 id_neg,
		     process_date , order_id
			 into #tb_order_fr_hist
		 FROM
			 #resultado 


		update A
		set result =
	    CASE 
	        WHEN symbol LIKE 'WIN%' THEN 
	            (net_value * min_quantity) * 0.20
	
	        WHEN symbol LIKE 'WDO%' THEN 
	             (net_value * min_quantity) * 10.00
	
	        WHEN symbol LIKE 'BIT%' THEN 
	            (net_value * min_quantity) * 0.10
	    END 
	FROM tb_order_fr_hist A
	WHERE 
	    (symbol LIKE 'WDO%' OR
	    symbol LIKE 'WIN%' OR
	    symbol LIKE 'BIT%')
		
	---insert ocorrencias
	insert into issues (account,date,alert_name,symbol,party_id,created_by,[rule],risk,[open],cvm_notification_date,bsm_notification_date,coaf_notification_date,adm_notification_date)
	SELECT 
	    account,
	    process_date,
	    'Front Running' AS alert_name,
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
	FROM #issues;



	------------------------------------------------------------------
	------------------------------------------------------------------		
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