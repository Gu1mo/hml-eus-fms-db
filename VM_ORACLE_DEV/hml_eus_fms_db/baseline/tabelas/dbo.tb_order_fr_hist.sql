CREATE TABLE [dbo].[tb_order_fr_hist] (
    [id_ord] int IDENTITY(1,1) NOT NULL,
    [order_id] bigint NOT NULL,
    [secondary_order_id] bigint NOT NULL,
    [account] bigint NOT NULL,
    [symbol] varchar(30) NOT NULL,
    [trade_id_text] varchar(MAX) NULL,
    [side] int NULL,
    [order_timestamp] time(7) NULL,
    [quantity] bigint NULL,
    [price] decimal(17,2) NULL,
    [side_value] decimal(17,2) NULL,
    [opposite_value] decimal(17,2) NULL,
    [net_value] decimal(17,2) NULL,
    [result_key] int NULL,
    [process_date] date NOT NULL,
    [min_quantity] bigint NULL,
    [result] decimal(17,2) NULL,
    [flag_recurrence] int NULL,
    [flag_cross] int NULL,
    CONSTRAINT [PK_tb_order_fr_hist] PRIMARY KEY ([order_id], [secondary_order_id], [account], [symbol], [process_date])
);

ALTER TABLE [dbo].[tb_order_fr_hist] ADD CONSTRAINT [FK_tb_order_fr_hist_1] FOREIGN KEY ([account], [symbol], [process_date]) REFERENCES [dbo].[tb_account_fr_hist] ([account], [symbol], [process_date]);