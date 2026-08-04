CREATE PROC [dbo].[usp_report_trade_extract_osc] @process_date DATE , @symbol VARCHAR(30) , @account INT 
AS

	--DECLARE	@process_date date 
	--	  , @symbol varchar(30) 
	--	  , @account int 

	 SELECT a.account
		  , a.symbol
		  , b.order_id
		  , b.secondary_order_id
		  , b.book_timestamp
		  , b.price
		  , b.quantity
		  , b.cumqty
		  , b.lastqty
		  , b.leavesqty
		  , case when b.side = '1' then 'Compra' else 'Venda' end as side
		  , case when b.trade_aggressor = 'A' then 'Comprador' when b.trade_aggressor = 'I' then 'Indefinido' when b.trade_aggressor = 'V' then 'Vendedor' end as trade_aggressor
		  , b.trade_buying_broker
		  , b.trade_id,trade_price
		  , b.trade_selling_broker		 
		 
	   FROM tb_account_osc_hist a 
  LEFT JOIN tb_order_osc_hist   b 
		 ON a.symbol	   = b.symbol
		AND a.account	   = b.account
		AND a.process_date = b.process_date
	  
	  WHERE a.process_date = isnull(@process_date ,a.process_date) 
		AND a.symbol	   = isnull(@symbol ,a.symbol)
		AND a.account	   = isnull(@account, a.account)

   ORDER BY a.account