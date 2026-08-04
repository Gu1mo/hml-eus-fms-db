CREATE TABLE [dbo].[tb_metrics_osc_hist] (
    [id_osc] bigint IDENTITY(1,1) NOT NULL,
    [account] bigint NULL,
    [symbol] varchar(30) NULL,
    [alert_type] varchar(30) NULL,
    [price] decimal(17,2) NULL,
    [client_weighted_avg] decimal(17,2) NULL,
    [market_weighted_avg] decimal(17,2) NULL,
    [market_weighted_stdev] decimal(17,4) NULL,
    [process_date] datetime2(7) NULL,
    [variation_client_pts] decimal(17,3) NULL,
    [variation_client_market] decimal(17,3) NULL,
    [prop_client] decimal(17,4) NULL,
    [prop_avg_market] decimal(17,4) NULL,
    CONSTRAINT [PK_tb_metrics_osc_hist] PRIMARY KEY ([id_osc])
);

ALTER TABLE [dbo].[tb_metrics_osc_hist] ADD CONSTRAINT [FK_tb_metrics_osc_hist_1] FOREIGN KEY ([account], [symbol], [process_date]) REFERENCES [dbo].[tb_account_osc_hist] ([account], [symbol], [process_date]);