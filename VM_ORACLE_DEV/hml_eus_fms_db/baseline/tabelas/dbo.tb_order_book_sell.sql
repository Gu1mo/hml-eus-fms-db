CREATE TABLE [dbo].[tb_order_book_sell] (
    [id_sell] bigint IDENTITY(1,1) NOT NULL,
    [order_key] bigint NULL,
    [secondary_order_id] bigint NULL,
    [sell_timestamp] datetime2(7) NULL,
    [symbol] varchar(20) NULL,
    [position] int NULL,
    [price] decimal(17,2) NULL,
    [quantity] bigint NULL,
    [sell_broker] int NULL,
    [process_date] date NULL,
    CONSTRAINT [PK_tb_order_book_sell] PRIMARY KEY ([id_sell])
);

CREATE INDEX [IDX_001] ON [dbo].[tb_order_book_sell] ([order_key], [position]);

CREATE INDEX [idx_01] ON [dbo].[tb_order_book_sell] ([order_key]);

ALTER TABLE [dbo].[tb_order_book_sell] ADD CONSTRAINT [FK_order_key_sell] FOREIGN KEY ([order_key]) REFERENCES [dbo].[tb_order] ([order_key]);