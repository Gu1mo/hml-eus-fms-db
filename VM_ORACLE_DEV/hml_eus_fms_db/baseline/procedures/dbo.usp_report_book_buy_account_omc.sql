CREATE PROCEDURE [dbo].[usp_report_book_buy_account_omc]  @account BIGINT  , @process_date DATETIME2 , @symbol VARCHAR(30) 

AS 

 --DECLARE @account BIGINT		 = 9856021
	--   , @process_date DATETIME2 = '2025-02-20'
	--   , @symbol VARCHAR(30)	 = 'GGPS3' 
	
    SELECT  A.order_key
		  , A.secondary_order_id
		  , A.buy_timestamp
		  , A.symbol
		  , A.position
		  , A.price
		  , A.quantity
		  , A.buy_broker
		  , A.process_date
		  , b.creation_timestamp
	  FROM tb_book_buy_omc_hist A
INNER JOIN  tb_order_omc_hist B
	    ON a.process_date = b.process_date
	   AND a.symbol = b.symbol
	   AND a.order_key = b.order_key
	 WHERE a.process_date = @process_date
	   AND a.symbol = @symbol  
	   AND b.account = @account