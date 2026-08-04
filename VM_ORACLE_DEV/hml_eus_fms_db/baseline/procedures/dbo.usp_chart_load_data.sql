CREATE proc [dbo].[usp_chart_load_data]	
	as
/*
Descrição de alterações
Dia:23/07/2024 Author: Guimo
Inclusão do tratamento de log, para quando rodar novamente o mesmo dia apague das tabelas destino e insira novamente.
Dessa forma evidenciando o reprocessamento pela tabela de log.

Dia:27/07/2024 Author: Guimo
- Alteração da processo de log retirando a condição de completed para reprocessar
*/
DECLARE @LogID INT;
DECLARE @log_process_date DATE = (SELECT max(process_date) FROM tb_order);

BEGIN TRY
    INSERT INTO log_ms (process, dt_exec, dt_begin,status_description,process_date)
    VALUES ('Load chart data', GETDATE(), GETDATE(), 'Started',@log_process_date);
    SET @LogID = SCOPE_IDENTITY();
	
	IF (SELECT COUNT(1) FROM log_ms WHERE process = 'Load chart data' AND process_date = @log_process_date ) > 0
	BEGIN
	
		PRINT 'reprocessing...'

		DELETE FROM chart_order_count  WHERE process_date = @log_process_date

	END
	ELSE
	BEGIN
		PRINT 'processing...'
	END;
		--------------------chart_order_count
		WITH qt_in AS (
			SELECT process_date 
				 , COUNT(DISTINCT secondary_order_id) in_order_quantity 
		     FROM tb_order
		 GROUP BY process_date
					)
		,qt_out as (
			SELECT process_date
				 , COUNT(secondary_order_id) out_order_quantity 
			  from (
				SELECT secondary_order_id,process_date 
				  FROM tb_order_book_buy 

				 UNION 

				SELECT secondary_order_id,process_date 
				  FROM tb_order_book_sell
					) x
			GROUP BY process_date
				   )

  INSERT INTO chart_order_count (process_date,in_order_quantity,out_order_quantity) 
	   SELECT a.process_date
		    , a.in_order_quantity
			, abs(b.out_order_quantity - a.in_order_quantity) AS out_order_quantity
		 FROM qt_in a 
	LEFT JOIN qt_out b 
		   ON a.process_date = b.process_date
		WHERE a.process_date not in (SELECT process_date FROM chart_order_count) 
----------------------------

    UPDATE log_ms
    SET dt_end = GETDATE(), duration = CAST(GETDATE() - dt_begin AS TIME), status_description = 'Completed'
    WHERE id_log = @LogID;

END TRY
BEGIN CATCH
	DECLARE @ERROR_MSG VARCHAR(1000) = ERROR_MESSAGE()
    UPDATE log_ms
	   SET dt_end = GETDATE()
		 , duration = CAST(GETDATE() - dt_begin AS TIME)
		 , status_description = 'Error: ' + ERROR_MESSAGE() + ' Error State:' +  cast(ERROR_STATE() as varchar)
     WHERE id_log = @LogID;

			 -- Fechar o cursor após uso
		CLOSE cursor_order;

		-- Desalocar o cursor para liberar recursos
		DEALLOCATE cursor_order;

	 RAISERROR(@ERROR_MSG, 16, 1)
END CATCH;