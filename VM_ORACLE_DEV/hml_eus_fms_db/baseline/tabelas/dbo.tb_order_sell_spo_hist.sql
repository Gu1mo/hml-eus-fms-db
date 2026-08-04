CREATE TABLE [dbo].[tb_order_sell_spo_hist] (
    [id_sell] bigint IDENTITY(1,1) NOT NULL,
    [order_key] bigint NULL,
    [related_order_key] bigint NOT NULL,
    [secondary_order_id] bigint NULL,
    [sell_timestamp] datetime2(7) NULL,
    [symbol] varchar(20) NULL,
    [position] int NULL,
    [price] decimal(17,2) NULL,
    [quantity] bigint NULL,
    [sell_broker] int NULL,
    [process_date] datetime2(7) NULL,
    CONSTRAINT [PK_tb_order_sell_spo_hist] PRIMARY KEY ([id_sell])
);

ALTER TABLE [dbo].[tb_order_sell_spo_hist] ADD CONSTRAINT [FK_tb_order_sell_spo_hist_1] FOREIGN KEY ([order_key], [related_order_key], [process_date]) REFERENCES [dbo].[tb_order_spo_cycle_hist] ([order_key], [related_order_key], [process_date]);