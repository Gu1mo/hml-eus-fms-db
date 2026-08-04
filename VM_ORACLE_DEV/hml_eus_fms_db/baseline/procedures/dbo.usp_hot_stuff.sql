CREATE   PROCEDURE dbo.usp_hot_stuff
    /* All defaulted: fira-4 calls this with no arguments. */
    @process_date date = NULL,   -- NULL = derive the newest date present in the source
    @keep_dates   int  = 7,      -- distinct dates retained in the archive
    @batch_size   int  = 50000   -- rows per DELETE batch, to bound log growth
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @target_db   sysname,
            @match_count int,
            @msg         nvarchar(2048),
            @sql         nvarchar(max),
            @qualified   nvarchar(400),
            @table_name  sysname,
            @date_column sysname,
            @cutoff_date date,
            @rows        bigint,
            @started_at  datetime2(3) = SYSDATETIME();

    IF @keep_dates IS NULL OR @keep_dates < 1
        THROW 50010, N'usp_hot_stuff: @keep_dates must be >= 1.', 1;

    IF @batch_size IS NULL OR @batch_size < 1
        THROW 50011, N'usp_hot_stuff: @batch_size must be >= 1.', 1;

    /* =============================================================== *
     * 1. Discover the archive database.
     * =============================================================== */
    SELECT @match_count = COUNT(*),
           @target_db   = MIN(d.name)
    FROM   sys.databases AS d
    WHERE  d.name LIKE N'%hotcold%'
      AND  d.database_id > 4        -- skip master/tempdb/model/msdb
      AND  d.state = 0              -- ONLINE only
      AND  d.name <> DB_NAME();     -- never treat the source as its own archive

    IF @match_count = 0
    BEGIN
        SET @msg = N'usp_hot_stuff: no ONLINE, non-system database matching ''%hotcold%'' is visible to login '''
                 + ISNULL(SUSER_SNAME(), N'?') + N''' on instance ''' + ISNULL(@@SERVERNAME, N'?')
                 + N'''. Either the archive database is absent/offline/misnamed, or this login has no'
                 + N' permission on it (sys.databases only returns databases the caller can see).';
        THROW 50012, @msg, 1;
    END

    IF @match_count > 1
    BEGIN
        SELECT @msg = N'usp_hot_stuff: expected exactly one database matching ''%hotcold%'' but found '
                    + CAST(@match_count AS nvarchar(10)) + N': '
                    + STRING_AGG(CAST(d.name AS nvarchar(128)), N', ')
        FROM   sys.databases AS d
        WHERE  d.name LIKE N'%hotcold%'
          AND  d.database_id > 4
          AND  d.state = 0
          AND  d.name <> DB_NAME();
        THROW 50013, @msg, 1;
    END

    /* =============================================================== *
     * 2. Table metadata. copy_order is FK-safe for inserts; deletes
     *    walk it in reverse. tb_quote is dated by symbol_timestamp,
     *    every other table by process_date.
     * =============================================================== */
    DECLARE @tables TABLE (
        copy_order  tinyint NOT NULL PRIMARY KEY,
        table_name  sysname NOT NULL,
        date_column sysname NOT NULL
    );

    INSERT @tables (copy_order, table_name, date_column) VALUES
        (1, N'tb_order',           N'process_date'),
        (2, N'tb_order_book_buy',  N'process_date'),
        (3, N'tb_order_book_sell', N'process_date'),
        (4, N'tb_entrypoint',      N'process_date'),
        (5, N'tb_quote',           N'symbol_timestamp'),
        (6, N'tb_trade',           N'process_date');

    /* Fail loudly, naming every missing table at once. */
    SELECT @msg = STRING_AGG(t.table_name, N', ')
    FROM   @tables AS t
    WHERE  OBJECT_ID(QUOTENAME(@target_db) + N'.dbo.' + QUOTENAME(t.table_name), N'U') IS NULL;

    IF @msg IS NOT NULL AND @msg <> N''
    BEGIN
        SET @msg = N'usp_hot_stuff: archive database ''' + @target_db
                 + N''' is missing table(s): ' + @msg
                 + N'. Run docs/hotcold-archive-schema.sql against it first.';
        THROW 50014, @msg, 1;
    END

    /* =============================================================== *
     * 3. Resolve the date to copy.
     * =============================================================== */
    IF @process_date IS NULL
        SELECT @process_date = MAX(d)
        FROM (
            SELECT MAX(process_date)     AS d FROM dbo.tb_order
            UNION ALL SELECT MAX(process_date)     FROM dbo.tb_order_book_buy
            UNION ALL SELECT MAX(process_date)     FROM dbo.tb_order_book_sell
            UNION ALL SELECT MAX(process_date)     FROM dbo.tb_entrypoint
            UNION ALL SELECT MAX(symbol_timestamp) FROM dbo.tb_quote
            UNION ALL SELECT MAX(process_date)     FROM dbo.tb_trade
        ) AS source_dates;

    IF @process_date IS NULL
    BEGIN
        /* Severity 10 = informational, not an error: an empty source means the
           transform loaded nothing, which the run already reported upstream. */
        SET @msg = N'usp_hot_stuff: no dated rows found in ' + DB_NAME()
                 + N'; nothing to copy to ''' + @target_db + N'''.';
        RAISERROR(@msg, 10, 1) WITH NOWAIT;
        RETURN 0;
    END

    SET @msg = N'usp_hot_stuff: copying ' + CONVERT(nvarchar(10), @process_date, 23)
             + N' from ''' + DB_NAME() + N''' to ''' + @target_db + N'''.';
    RAISERROR(@msg, 10, 1) WITH NOWAIT;

    /* =============================================================== *
     * 4. Clear the target date from the archive (children first).
     *
     *    Batched so a re-copy of a heavy order-book date does not blow the
     *    log with one enormous DELETE.
     * =============================================================== */
    DECLARE delete_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT table_name, date_column FROM @tables ORDER BY copy_order DESC;

    OPEN delete_cursor;
    FETCH NEXT FROM delete_cursor INTO @table_name, @date_column;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @qualified = QUOTENAME(@target_db) + N'.dbo.' + QUOTENAME(@table_name);
        SET @sql = N'
DECLARE @batch_rows int = 1;
WHILE @batch_rows > 0
BEGIN
    DELETE TOP (' + CAST(@batch_size AS nvarchar(20)) + N')
    FROM ' + @qualified + N'
    WHERE ' + QUOTENAME(@date_column) + N' = @d;
    SET @batch_rows = @@ROWCOUNT;
END';
        EXEC sys.sp_executesql @sql, N'@d date', @d = @process_date;

        FETCH NEXT FROM delete_cursor INTO @table_name, @date_column;
    END

    CLOSE delete_cursor;
    DEALLOCATE delete_cursor;

    /* =============================================================== *
     * 5. Copy, in FK-safe order.
     *
     *    Column lists are explicit so a future column added to one side
     *    fails loudly instead of silently shifting data.
     * =============================================================== */

    /* --- tb_order (parent of both book tables) --------------------- */
    SET @sql = N'
INSERT INTO ' + QUOTENAME(@target_db) + N'.dbo.tb_order
    (order_key, order_id, secondary_order_id, account, order_timestamp, msg_type,
     party_id, price, last_px, quantity, cumqty, lastqty, leavesqty, side, symbol,
     exec_type, ord_status, process_date, book_timestamp, book_spread, order_spread,
     trade_id, source_id, trading_session_sub_id)
SELECT
     order_key, order_id, secondary_order_id, account, order_timestamp, msg_type,
     party_id, price, last_px, quantity, cumqty, lastqty, leavesqty, side, symbol,
     exec_type, ord_status, process_date, book_timestamp, book_spread, order_spread,
     trade_id, source_id, trading_session_sub_id
FROM dbo.tb_order
WHERE process_date = @d;
SET @out_rows = ROWCOUNT_BIG();';
    EXEC sys.sp_executesql @sql, N'@d date, @out_rows bigint OUTPUT',
         @d = @process_date, @out_rows = @rows OUTPUT;
    RAISERROR(N'  tb_order: %I64d row(s).', 10, 1, @rows) WITH NOWAIT;

    /* --- tb_order_book_buy (id_buy left to the archive IDENTITY) --- */
    SET @sql = N'
INSERT INTO ' + QUOTENAME(@target_db) + N'.dbo.tb_order_book_buy
    (order_key, secondary_order_id, buy_timestamp, symbol, [position], price,
     quantity, buy_broker, process_date)
SELECT
     order_key, secondary_order_id, buy_timestamp, symbol, [position], price,
     quantity, buy_broker, process_date
FROM dbo.tb_order_book_buy
WHERE process_date = @d;
SET @out_rows = ROWCOUNT_BIG();';
    EXEC sys.sp_executesql @sql, N'@d date, @out_rows bigint OUTPUT',
         @d = @process_date, @out_rows = @rows OUTPUT;
    RAISERROR(N'  tb_order_book_buy: %I64d row(s).', 10, 1, @rows) WITH NOWAIT;

    /* --- tb_order_book_sell (id_sell left to the archive IDENTITY) - */
    SET @sql = N'
INSERT INTO ' + QUOTENAME(@target_db) + N'.dbo.tb_order_book_sell
    (order_key, secondary_order_id, sell_timestamp, symbol, [position], price,
     quantity, sell_broker, process_date)
SELECT
     order_key, secondary_order_id, sell_timestamp, symbol, [position], price,
     quantity, sell_broker, process_date
FROM dbo.tb_order_book_sell
WHERE process_date = @d;
SET @out_rows = ROWCOUNT_BIG();';
    EXEC sys.sp_executesql @sql, N'@d date, @out_rows bigint OUTPUT',
         @d = @process_date, @out_rows = @rows OUTPUT;
    RAISERROR(N'  tb_order_book_sell: %I64d row(s).', 10, 1, @rows) WITH NOWAIT;

    /* --- tb_entrypoint -------------------------------------------- */
    SET @sql = N'
INSERT INTO ' + QUOTENAME(@target_db) + N'.dbo.tb_entrypoint
    (id, order_id, secondary_order_id, account, order_timestamp, msg_type, party_id,
     price, last_px, quantity, cumqty, lastqty, leavesqty, side, symbol, exec_type,
     ord_status, process_date, trade_id, trading_session_sub_id)
SELECT
     id, order_id, secondary_order_id, account, order_timestamp, msg_type, party_id,
     price, last_px, quantity, cumqty, lastqty, leavesqty, side, symbol, exec_type,
     ord_status, process_date, trade_id, trading_session_sub_id
FROM dbo.tb_entrypoint
WHERE process_date = @d;
SET @out_rows = ROWCOUNT_BIG();';
    EXEC sys.sp_executesql @sql, N'@d date, @out_rows bigint OUTPUT',
         @d = @process_date, @out_rows = @rows OUTPUT;
    RAISERROR(N'  tb_entrypoint: %I64d row(s).', 10, 1, @rows) WITH NOWAIT;

    /* --- tb_quote (dated by symbol_timestamp) --------------------- */
    SET @sql = N'
INSERT INTO ' + QUOTENAME(@target_db) + N'.dbo.tb_quote
    (id_quote, symbol, open_price, min_price, avg_price, max_price, close_price,
     yesterday_close_price, trade_count, financial_volume, symbol_timestamp)
SELECT
     id_quote, symbol, open_price, min_price, avg_price, max_price, close_price,
     yesterday_close_price, trade_count, financial_volume, symbol_timestamp
FROM dbo.tb_quote
WHERE symbol_timestamp = @d;
SET @out_rows = ROWCOUNT_BIG();';
    EXEC sys.sp_executesql @sql, N'@d date, @out_rows bigint OUTPUT',
         @d = @process_date, @out_rows = @rows OUTPUT;
    RAISERROR(N'  tb_quote: %I64d row(s).', 10, 1, @rows) WITH NOWAIT;

    /* --- tb_trade ------------------------------------------------- */
    SET @sql = N'
INSERT INTO ' + QUOTENAME(@target_db) + N'.dbo.tb_trade
    (id_trade, msg_time, header, symbol, task, price, quantity, trade_time,
     broker_buy, broker_sell, trade_id, direct, aggressor, process_date)
SELECT
     id_trade, msg_time, header, symbol, task, price, quantity, trade_time,
     broker_buy, broker_sell, trade_id, direct, aggressor, process_date
FROM dbo.tb_trade
WHERE process_date = @d;';
    EXEC sys.sp_executesql @sql, N'@d date', @d = @process_date;
    SET @rows = ROWCOUNT_BIG();
    RAISERROR(N'  tb_trade: %I64d row(s).', 10, 1, @rows) WITH NOWAIT;

    /* =============================================================== *
     * 6. Retention: keep the newest @keep_dates distinct dates.
     *
     *    The cutoff is the oldest date being kept; anything strictly
     *    older is pruned from every table. Fewer than @keep_dates dates
     *    present => cutoff is the oldest date => nothing is deleted.
     * =============================================================== */
    SET @sql = N'
SELECT @cutoff = MIN(d)
FROM (
    SELECT TOP (@keep) d
    FROM (
        SELECT DISTINCT process_date     AS d FROM ' + QUOTENAME(@target_db) + N'.dbo.tb_order
        UNION SELECT DISTINCT process_date      FROM ' + QUOTENAME(@target_db) + N'.dbo.tb_order_book_buy
        UNION SELECT DISTINCT process_date      FROM ' + QUOTENAME(@target_db) + N'.dbo.tb_order_book_sell
        UNION SELECT DISTINCT process_date      FROM ' + QUOTENAME(@target_db) + N'.dbo.tb_entrypoint
        UNION SELECT DISTINCT symbol_timestamp  FROM ' + QUOTENAME(@target_db) + N'.dbo.tb_quote
        UNION SELECT DISTINCT process_date      FROM ' + QUOTENAME(@target_db) + N'.dbo.tb_trade
    ) AS archive_dates
    ORDER BY d DESC
) AS kept;';
    EXEC sys.sp_executesql @sql,
         N'@keep int, @cutoff date OUTPUT',
         @keep = @keep_dates, @cutoff = @cutoff_date OUTPUT;

    IF @cutoff_date IS NOT NULL
    BEGIN
        DECLARE prune_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT table_name, date_column FROM @tables ORDER BY copy_order DESC;

        OPEN prune_cursor;
        FETCH NEXT FROM prune_cursor INTO @table_name, @date_column;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @qualified = QUOTENAME(@target_db) + N'.dbo.' + QUOTENAME(@table_name);
            SET @sql = N'
DECLARE @batch_rows int = 1;
WHILE @batch_rows > 0
BEGIN
    DELETE TOP (' + CAST(@batch_size AS nvarchar(20)) + N')
    FROM ' + @qualified + N'
    WHERE ' + QUOTENAME(@date_column) + N' < @cutoff;
    SET @batch_rows = @@ROWCOUNT;
END';
            EXEC sys.sp_executesql @sql, N'@cutoff date', @cutoff = @cutoff_date;

            FETCH NEXT FROM prune_cursor INTO @table_name, @date_column;
        END

        CLOSE prune_cursor;
        DEALLOCATE prune_cursor;

        SET @msg = N'usp_hot_stuff: retention kept the newest '
                 + CAST(@keep_dates AS nvarchar(10)) + N' date(s); pruned everything before '
                 + CONVERT(nvarchar(10), @cutoff_date, 23) + N'.';
        RAISERROR(@msg, 10, 1) WITH NOWAIT;
    END

    SET @msg = N'usp_hot_stuff: finished in '
             + CAST(DATEDIFF(millisecond, @started_at, SYSDATETIME()) / 1000.0 AS nvarchar(20))
             + N' second(s).';
    RAISERROR(@msg, 10, 1) WITH NOWAIT;

    RETURN 0;
END