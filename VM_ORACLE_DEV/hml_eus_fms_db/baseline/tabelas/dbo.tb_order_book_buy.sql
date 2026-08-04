CREATE TABLE [dbo].[tb_order_book_buy] (
    [id_buy] bigint IDENTITY(1,1) NOT NULL,
    [order_key] bigint NULL,
    [secondary_order_id] bigint NULL,
    [buy_timestamp] datetime2(7) NULL,
    [symbol] varchar(20) NULL,
    [position] int NULL,
    [price] decimal(17,2) NULL,
    [quantity] bigint NULL,
    [buy_broker] int NULL,
    [process_date] date NULL,
    CONSTRAINT [PK_tb_order_book_buy] PRIMARY KEY ([id_buy])
);

CREATE INDEX [IDX_001] ON [dbo].[tb_order_book_buy] ([symbol], [buy_broker], [secondary_order_id], [buy_timestamp]);

CREATE INDEX [IDX_002] ON [dbo].[tb_order_book_buy] ([order_key], [position]);

ALTER TABLE [dbo].[tb_order_book_buy] ADD CONSTRAINT [FK_order_key_buy] FOREIGN KEY ([order_key]) REFERENCES [dbo].[tb_order] ([order_key]);