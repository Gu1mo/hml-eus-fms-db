CREATE   PROCEDURE [dbo].[PR_GRAPHIC_LAYERING]
    @account VARCHAR(255) = NULL  -- Permitindo chamadas sem especificar account
AS
BEGIN
    SET NOCOUNT ON;

    -- Verificando se account foi fornecido
    IF @account IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM tb_order_layer_hist WHERE account = @account)
        BEGIN
            DECLARE @relatedOrderKeys TABLE (related_order_key BIGINT);

            INSERT INTO @relatedOrderKeys
            SELECT DISTINCT related_order_key
            FROM tb_order_layer_cycle_hist
            WHERE account = @account;

            SELECT b.*
            INTO #BuyOrders
            FROM tb_order_buy_layer_hist b
            INNER JOIN @relatedOrderKeys k ON b.related_order_key = k.related_order_key;

            SELECT s.*
            INTO #SellOrders
            FROM tb_order_sell_layer_hist s
            INNER JOIN @relatedOrderKeys k ON s.related_order_key = k.related_order_key;

            SELECT 
                (SELECT * FROM #SellOrders FOR JSON PATH) AS sellOrdens,
                (SELECT * FROM #BuyOrders FOR JSON PATH) AS buyOrdens,
                (SELECT * FROM tb_order_layer_cycle_hist WHERE account = @account FOR JSON PATH) AS cycleOrdens,
                (SELECT * FROM tb_order_layer_hist WHERE account = @account FOR JSON PATH) AS tableOrdens;

            DROP TABLE #BuyOrders;
            DROP TABLE #SellOrders;
        END
    ELSE
        BEGIN
            SELECT 
                '{}' AS sellOrdens,
                '{}' AS buyOrdens,
                (SELECT * FROM tb_order_layer_cycle_hist WHERE account = @account FOR JSON PATH) AS cycleOrdens,
                (SELECT * FROM tb_order_layer_hist WHERE account = @account FOR JSON PATH) AS tableOrdens;
        END
    END
    ELSE
    BEGIN
        SELECT 
            (SELECT * FROM tb_order_sell_layer_hist FOR JSON PATH) AS sellOrdens,
            (SELECT * FROM tb_order_buy_layer_hist FOR JSON PATH) AS buyOrdens,
            (SELECT * FROM tb_order_layer_cycle_hist FOR JSON PATH) AS cycleOrdens,
            (SELECT * FROM tb_order_layer_hist FOR JSON PATH) AS tableOrdens;
    END
END