CREATE TABLE [dbo].[tb_opposite_fr_hist] (
    [id_opp] int IDENTITY(1,1) NOT NULL,
    [order_id] bigint NOT NULL,
    [secondary_order_id] bigint NOT NULL,
    [account] bigint NOT NULL,
    [symbol] varchar(30) NOT NULL,
    [trade_id] bigint NOT NULL,
    [side] int NULL,
    [order_timestamp] time(7) NULL,
    [quantity] bigint NULL,
    [price] decimal(17,2) NULL,
    [result_key] int NOT NULL,
    [process_date] date NOT NULL,
    [flag_cross] int NULL,
    CONSTRAINT [PK_tb_opposite_fr_hist] PRIMARY KEY ([order_id], [secondary_order_id], [account], [symbol], [trade_id], [result_key], [process_date])
);

ALTER TABLE [dbo].[tb_opposite_fr_hist] ADD CONSTRAINT [FK_tb_opposite_fr_hist_1] FOREIGN KEY ([account], [symbol], [process_date]) REFERENCES [dbo].[tb_account_fr_hist] ([account], [symbol], [process_date]);