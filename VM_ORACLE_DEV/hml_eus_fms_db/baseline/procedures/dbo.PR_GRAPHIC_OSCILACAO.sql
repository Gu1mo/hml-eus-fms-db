CREATE PROCEDURE [dbo].[PR_GRAPHIC_OSCILACAO]
    @account NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Seleciona dados da tabela tb_account_osc_hist
    SELECT 'tb_account_osc_hist' AS tableName, *
    FROM tb_account_osc_hist
    WHERE account = @account;

    -- Seleciona dados da tabela tb_metrics_osc_hist
    SELECT 'tb_metrics_osc_hist' AS tableName, *
    FROM tb_metrics_osc_hist
    WHERE account = @account;

    -- Seleciona dados da tabela tb_order_osc_hist
    SELECT 'tb_order_osc_hist' AS tableName, *
    FROM tb_order_osc_hist
    WHERE account = @account;

    -- Seleciona dados da tabela tb_symbol_osc_hist
    SELECT 'tb_symbol_osc_hist' AS tableName, *
    FROM tb_symbol_osc_hist
END;