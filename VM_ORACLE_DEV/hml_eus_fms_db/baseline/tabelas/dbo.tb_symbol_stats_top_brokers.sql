CREATE TABLE [dbo].[tb_symbol_stats_top_brokers] (
    [id_top_broker] int IDENTITY(1,1) NOT NULL,
    [process_date] date NOT NULL,
    [symbol] varchar(20) NOT NULL,
    [rank_pos] tinyint NOT NULL,
    [broker_id] varchar(50) NOT NULL,
    [broker_volume] decimal(18,2) NULL,
    [broker_trade_count] int NULL,
    [created_at] datetime2(3) NOT NULL DEFAULT (getdate()),
    CONSTRAINT [PK_tb_symbol_stats_top_brokers] PRIMARY KEY ([id_top_broker])
);

CREATE INDEX [IX_tb_sstb_date_symbol] ON [dbo].[tb_symbol_stats_top_brokers] ([process_date], [symbol]);