CREATE TABLE [dbo].[tb_book_buy_omc_hist] (
    [id_buy] bigint IDENTITY(1,1) NOT NULL,
    [order_key] bigint NULL,
    [secondary_order_id] bigint NULL,
    [buy_timestamp] datetime2(7) NULL,
    [symbol] varchar(20) NULL,
    [position] int NULL,
    [price] decimal(17,2) NULL,
    [quantity] bigint NULL,
    [buy_broker] int NULL,
    [process_date] datetime2(7) NULL
);

ALTER TABLE [dbo].[tb_book_buy_omc_hist] ADD CONSTRAINT [FK_tb_book_buy_omc_hist_1] FOREIGN KEY ([order_key], [process_date]) REFERENCES [dbo].[tb_order_omc_hist] ([order_key], [process_date]);