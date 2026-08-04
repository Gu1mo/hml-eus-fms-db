CREATE TABLE [dbo].[tb_metrics_omc_hist] (
    [id_metrics] int IDENTITY(1,1) NOT NULL,
    [account] bigint NOT NULL,
    [symbol] varchar(30) NOT NULL,
    [trade_id] bigint NOT NULL,
    [flag_auction] bit NOT NULL,
    [flag_oscillation] bit NOT NULL,
    [flag_aggressor] bit NOT NULL,
    [flag_quantity] bit NOT NULL,
    [process_date] datetime2(7) NOT NULL,
    [flag_cross] int NULL,
    [flag_recurrence] int NULL,
    CONSTRAINT [PK_tb_metrics_omc_hist] PRIMARY KEY ([symbol], [trade_id], [process_date])
);

ALTER TABLE [dbo].[tb_metrics_omc_hist] ADD CONSTRAINT [FK_tb_metrics_omc_hist_1] FOREIGN KEY ([account], [symbol], [process_date]) REFERENCES [dbo].[tb_account_omc_hist] ([account], [symbol], [process_date]);