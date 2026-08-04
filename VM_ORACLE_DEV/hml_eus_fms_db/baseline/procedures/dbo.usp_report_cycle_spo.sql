create PROC [dbo].[usp_report_cycle_spo] @process_date DATE , @symbol VARCHAR(30) , @account INT 
as 
   SELECT a.account 
	    , a.symbol
		, b.order_id
		, b.secondary_order_id
		, b.book_timestamp
		, b.price
		, b.quantity
		, case when b.side = 1 then 'Compra' else 'Venda' end side
		, case when b.exec_type = '0' then 'Criação' when b.exec_type = '4' then 'Cancelada' when b.exec_type = 'F' then 'Trade' when b.exec_type = '5' then 'Substituída' end status_oferta
		, b.book_spread
		, b.order_spread
	 FROM tb_account_spo_hist a
LEFT JOIN tb_order_spo_cycle_hist b
	   ON a.account = b.account
	  AND a.symbol= b.symbol
	  AND a.process_date = b.process_date
	WHERE a.process_date = isnull(@process_date ,a.process_date) 
	  AND a.symbol	   = isnull(@symbol ,a.symbol)
	  AND a.account	   = isnull(@account, a.account)

   ORDER BY a.account