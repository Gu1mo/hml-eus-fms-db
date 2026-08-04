CREATE PROCEDURE [dbo].[usp_report_book_buy_omc]  @order_key BIGINT  , @process_date DATETIME2 , @symbol VARCHAR(30) 

as
--DECLARE @order_key bigint = 38610
--	  , @process_date datetime2 = '2024-06-19'
--	  , @symbol varchar(30) = 'WINQ24'

	 SELECT order_key
		  , secondary_order_id
		  , buy_timestamp
		  , symbol
		  , position
		  , price
		  , quantity
		  , buy_broker
		  , process_date
	   FROM tb_book_buy_omc_hist
	  WHERE order_key	 = @order_key
	    AND process_date = @process_date
	    AND symbol		 = @symbol
   ORDER BY position ASC
	  --tb_book_buy_omc_hist
--tb_book_sell_omc_hist