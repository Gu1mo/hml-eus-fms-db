CREATE PROC [dbo].[usp_report_metrics_osc] @process_date DATE , @symbol VARCHAR(30) , @account INT 
AS
	SELECT  a.account
		  , a.symbol
		  , c.alert_type
		  , c.client_weighted_avg
		  , c.market_weighted_avg
		  , c.market_weighted_stdev
		  , d.ratio
		  , c.variation_client_pts
		  , c.variation_client_market
	   FROM tb_account_osc_hist a
  LEFT JOIN tb_metrics_osc_hist c  
		 ON a.symbol	   = c.symbol
	    AND a.account	   = c.account
	    AND a.process_date = c.process_date
  LEFT JOIN tb_symbol_osc_hist d
	     ON a.symbol	   = d.symbol
		AND a.process_date = d.process_date
	  
	  WHERE a.process_date = isnull(@process_date ,a.process_date) 
		AND a.symbol	   = isnull(@symbol ,a.symbol)
		AND a.account	   = isnull(@account, a.account)

   ORDER BY a.account