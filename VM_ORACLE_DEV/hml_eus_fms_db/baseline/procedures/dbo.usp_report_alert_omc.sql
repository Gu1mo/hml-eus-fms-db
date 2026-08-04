CREATE PROC [dbo].[usp_report_alert_omc]  @account BIGINT,@process_date DATETIME2, @symbol VARCHAR(30)

as

--DECLARE @account bigint = 1363282
--	  , @process_date datetime2  = '2024-06-19 00:00:00.0000000'
--	  , @symbol varchar(30) = 'WINQ24'

	SELECT a.account
		 , a.symbol
		 , a.process_date
		 , a.trade_id
		 , b.trade_time
		 , CASE WHEN b.aggressor = 'A' THEN 'Comprador' when b.aggressor = 'I' then 'Indefinido' when b.aggressor = 'V' then 'Vendedor' end side_aggressor
		 , a.flag_auction
		 , a.flag_oscillation
		 , a.flag_aggressor
		 , a.flag_quantity
		 , a.flag_cross
		 , a.flag_recurrence
		 , b.volume
	 FROM tb_metrics_omc_hist a  
LEFT JOIN tb_trade_omc_hist b 
	   ON a.trade_id = b.trade_id
	  AND a.process_date = b.process_date
	  AND a.symbol = b.symbol

	WHERE a.account      = isnull(@account,a.account)
	  and a.symbol		 = isnull(@symbol,a.symbol)
	  and a.process_date = isnull(@process_date,a.process_date);