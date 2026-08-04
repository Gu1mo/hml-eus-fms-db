CREATE TABLE [dbo].[tb_expressive_fr_hist] (
    [id_exp] int IDENTITY(1,1) NOT NULL,
    [account] bigint NULL,
    [symbol] varchar(30) NULL,
    [trade_id] bigint NULL,
    [expressive_quantity] bigint NULL,
    [expressive_trade_id] int NULL,
    [broker_buy] int NULL,
    [broker_sell] int NULL,
    [trade_time] time(7) NULL,
    [avg_quantity] bigint NULL,
    [stdev_quantity] bigint NULL,
    [result_key] int NULL,
    [process_date] date NULL,
    [expressive_price] decimal(17,2) NULL
);

ALTER TABLE [dbo].[tb_expressive_fr_hist] ADD CONSTRAINT [FK_tb_expressive_fr_hist_1] FOREIGN KEY ([account], [symbol], [process_date]) REFERENCES [dbo].[tb_account_fr_hist] ([account], [symbol], [process_date]);