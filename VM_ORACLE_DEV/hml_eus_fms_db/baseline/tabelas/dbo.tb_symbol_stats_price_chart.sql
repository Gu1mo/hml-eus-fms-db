CREATE TABLE [dbo].[tb_symbol_stats_price_chart] (
    [id_price_chart] int IDENTITY(1,1) NOT NULL,
    [process_date] date NOT NULL,
    [symbol] varchar(20) NOT NULL,
    [interval_start] time(0) NOT NULL,
    [open_price] decimal(18,4) NULL,
    [high_price] decimal(18,4) NULL,
    [low_price] decimal(18,4) NULL,
    [close_price] decimal(18,4) NULL,
    [volume] decimal(18,2) NULL,
    [trade_count] int NULL,
    [created_at] datetime2(3) NOT NULL DEFAULT (getdate()),
    CONSTRAINT [PK_tb_symbol_stats_price_chart] PRIMARY KEY ([id_price_chart])
);

CREATE INDEX [IX_tb_sspc_date_symbol] ON [dbo].[tb_symbol_stats_price_chart] ([process_date], [symbol]);