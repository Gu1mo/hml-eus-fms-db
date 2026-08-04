CREATE TABLE [dbo].[tb_quote] (
    [id_quote] bigint NOT NULL,
    [symbol] varchar(30) NULL,
    [open_price] decimal(17,4) NULL,
    [min_price] decimal(17,4) NULL,
    [avg_price] decimal(17,4) NULL,
    [max_price] decimal(17,4) NULL,
    [close_price] decimal(17,4) NULL,
    [yesterday_close_price] decimal(17,4) NULL,
    [trade_count] bigint NULL,
    [financial_volume] decimal(17,4) NULL,
    [symbol_timestamp] date NULL,
    CONSTRAINT [PK_tb_quote] PRIMARY KEY ([id_quote])
);

CREATE INDEX [IDX_001] ON [dbo].[tb_quote] ([symbol]);