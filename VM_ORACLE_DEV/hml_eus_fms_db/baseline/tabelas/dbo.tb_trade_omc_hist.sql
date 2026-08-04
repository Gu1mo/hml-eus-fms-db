CREATE TABLE [dbo].[tb_trade_omc_hist] (
    [id_trade] bigint IDENTITY(1,1) NOT NULL,
    [msg_time] time(7) NULL,
    [header] char(1) NULL,
    [symbol] varchar(30) NOT NULL,
    [task] char(1) NULL,
    [price] decimal(17,2) NULL,
    [quantity] bigint NULL,
    [avg_quantity] int NULL,
    [stdev_quantity] decimal(20,4) NULL,
    [trade_time] time(7) NOT NULL,
    [broker_buy] int NULL,
    [broker_sell] int NULL,
    [trade_id] bigint NOT NULL,
    [direct] int NULL,
    [aggressor] char(1) NULL,
    [process_date] datetime2(7) NOT NULL,
    [volume] decimal(17,3) NULL,
    CONSTRAINT [PK_tb_trade_omc_hist] PRIMARY KEY ([symbol], [trade_id], [process_date], [trade_time])
);

ALTER TABLE [dbo].[tb_trade_omc_hist] ADD CONSTRAINT [FK_tb_trade_omc_hist_2] FOREIGN KEY ([symbol], [trade_id], [process_date]) REFERENCES [dbo].[tb_metrics_omc_hist] ([symbol], [trade_id], [process_date]);