CREATE proc [dbo].[usp_report_detail_omc] @account BIGINT,@process_date DATETIME2, @symbol VARCHAR(30) , @trade_id bigint
 as

/*
26/07/2024 - Author: Guimo
-Inclusão da coluna de quantidade total.
*/
 --DECLARE @account BIGINT,@process_date DATETIME2 = '2024-07-24', @symbol VARCHAR(30) , @trade_id bigint

  SELECT  a.order_id
	    , a.secondary_order_id
	    , a.account
		, a.symbol
		, a.process_date
	    , a.order_timestamp
	    , a.book_timestamp		
	    , b.trade_time
	    , a.trade_id
		, CASE WHEN a.side = '1' THEN 'Compra' else 'Venda' end as side
	    , b.price
	    , b.quantity
		, a.quantity total_quantity
		, b.avg_quantity avg_quantity_book
		, b.stdev_quantity stdev_quantity_book
	    , CASE WHEN a.side = '1' THEN 'Compra' else 'Venda' end as side
	    , CASE WHEN b.aggressor = 'A' THEN 'Comprador' when b.aggressor = 'I' then 'Indefinido' when b.aggressor = 'V' then 'Vendedor' end as side_aggressor
	    , CASE WHEN c.flag_auction = 1		THEN 'SIM' ELSE 'NÃO' END auction
	    , CASE WHEN c.flag_oscillation = 1 THEN 'SIM' ELSE 'NÃO' END oscillation 
	    , CASE WHEN c.flag_aggressor = 1   THEN 'SIM' ELSE 'NÃO' END aggressor	
		, CASE WHEN c.flag_quantity = 1   THEN 'SIM' ELSE 'NÃO' END avg_quantity
		
	 FROM tb_order_omc_hist a
LEFT JOIN tb_trade_omc_hist b 
	   ON a.trade_id = b.trade_id
	  AND a.process_date = b.process_date
	  AND a.symbol = b.symbol
LEFT JOIN tb_metrics_omc_hist c
	   ON a.trade_id = c.trade_id
	  AND a.process_date = c.process_date
	  AND a.symbol = c.symbol
	WHERE a.account      = isnull(@account,a.account)
	  and a.symbol		 = isnull(@symbol,a.symbol)
	  and a.process_date = isnull(@process_date,a.process_date)
	  and a.trade_id = isnull(@trade_id,a.trade_id)
 ORDER BY symbol 
	    , trade_id