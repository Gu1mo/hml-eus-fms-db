CREATE PROC [dbo].[usp_report_trade_omc]  @account BIGINT,@process_date DATETIME2, @symbol VARCHAR(30) , @trade_id bigint
 as
--declare @account BIGINT = '1363282'
--,@process_date DATETIME2 ='2024-06-19'
--, @symbol VARCHAR(30)  = 'WINQ24'
--, @trade_id bigint = '52096790'
SELECT	a.order_key
		, a.order_id
	    , a.secondary_order_id
	    , a.symbol
	    , a.account
	    , a.order_timestamp
	    , a.book_timestamp
	    , b.trade_time
	    , a.trade_id
		, CASE WHEN a.side = '1' THEN 'Compra' else 'Venda' end as side
	    , b.price
	    , b.quantity
		, a.process_date
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