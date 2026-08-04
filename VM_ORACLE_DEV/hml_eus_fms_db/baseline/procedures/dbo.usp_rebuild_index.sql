CREATE procedure [dbo].[usp_rebuild_index]

as
/*
	25/07/2025 - Author: Guimo

	-Ajuste no try cacth para fechar o cursor correto
	-Ajuste no processo de insert na tabela de log

17/06/2026 - Fix: Removido COMMIT/ROLLBACK pois a SP nao abre transacao propria.
              O driver ODBC gerencia a transacao externa; COMMIT aqui causava erro 266 (@@TRANCOUNT 1->0).
*/
DECLARE @LogID INT;
DECLARE @log_process_date DATE = (SELECT max(process_date) FROM tb_order);

BEGIN TRY
    INSERT INTO log_ms (process, dt_exec, dt_begin,status_description,process_date)
    VALUES ('Rebuild Index', GETDATE(), GETDATE(), 'Started',@log_process_date);
    SET @LogID = SCOPE_IDENTITY();


			DECLARE @nmTable NVARCHAR(128);
			DECLARE @nmIndex NVARCHAR(128);
			DECLARE @action NVARCHAR(20);
			DECLARE @sql NVARCHAR(MAX);

			DECLARE cursor_index  CURSOR FOR
			WITH tb_index AS (
				SELECT 
					dbschemas.[name] as 'Schema',
					dbtables.[name] as nmTable,
					dbindexes.[name] as nmIndex,
					indexstats.alloc_unit_type_desc as 'Allocation Unit Type',
					indexstats.avg_fragmentation_in_percent as 'Fragmentation',
					indexstats.page_count as 'Page Count',
					CASE
						WHEN indexstats.avg_fragmentation_in_percent >= 30 THEN 'REBUILD'
						WHEN indexstats.avg_fragmentation_in_percent >= 10 THEN 'REORGANIZE'
						ELSE 'OK'
					END as 'Action'
				FROM 
					sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL , NULL, 'LIMITED') indexstats
					INNER JOIN sys.indexes dbindexes ON dbindexes.[object_id] = indexstats.[object_id]
													   AND dbindexes.[index_id] = indexstats.[index_id]
					INNER JOIN sys.objects dbtables ON dbindexes.[object_id] = dbtables.[object_id]
					INNER JOIN sys.schemas dbschemas ON dbtables.[schema_id] = dbschemas.[schema_id]
				WHERE 
					indexstats.database_id = DB_ID() 
	
			)
			SELECT nmTable, nmIndex, Action FROM tb_index;

			OPEN cursor_index;

			FETCH NEXT FROM cursor_index INTO @nmTable, @nmIndex, @action;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				SET @sql = '';
    
				IF @action = 'REBUILD'
				BEGIN 
					PRINT 'ALTER INDEX [' + @nmIndex + '] ON [' + @nmTable + '] REBUILD;';
					SET @sql = 'ALTER INDEX [' + @nmIndex + '] ON [' + @nmTable + '] REBUILD;';
				END
				ELSE IF @action = 'REORGANIZE'
				BEGIN
					print 'ALTER INDEX [' + @nmIndex + '] ON [' + @nmTable + '] REORGANIZE;';

					SET @sql = 'ALTER INDEX [' + @nmIndex + '] ON [' + @nmTable + '] REORGANIZE;';
				END
    
				IF @sql <> ''
				BEGIN
					EXEC sp_executesql @sql;
				END
    
				FETCH NEXT FROM cursor_index INTO @nmTable, @nmIndex, @action;
			END

			CLOSE cursor_index;
			DEALLOCATE cursor_index;


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


	IF CURSOR_STATUS('global', 'cursor_index') >= 0
	BEGIN
	    -- Close the cursor
	    CLOSE cursor_index;
	END;
	
	IF CURSOR_STATUS('global', 'cursor_index') >= -1
	BEGIN
	    -- Deallocate the cursor
	    DEALLOCATE cursor_index;
	END;

	 RAISERROR(@ERROR_MSG, 16, 1)
END CATCH;