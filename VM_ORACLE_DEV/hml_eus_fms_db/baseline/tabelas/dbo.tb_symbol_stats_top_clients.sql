CREATE TABLE [dbo].[tb_symbol_stats_top_clients] (
    [id_top_client] int IDENTITY(1,1) NOT NULL,
    [process_date] date NOT NULL,
    [symbol] varchar(20) NOT NULL,
    [rank_pos] tinyint NOT NULL,
    [account] varchar(50) NOT NULL,
    [client_volume] decimal(18,2) NULL,
    [client_qty] decimal(18,2) NULL,
    [client_trade_count] int NULL,
    [created_at] datetime2(3) NOT NULL DEFAULT (getdate()),
    CONSTRAINT [PK_tb_symbol_stats_top_clients] PRIMARY KEY ([id_top_client])
);

CREATE INDEX [IX_tb_sstc_date_symbol] ON [dbo].[tb_symbol_stats_top_clients] ([process_date], [symbol]);