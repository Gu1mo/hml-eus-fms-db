CREATE TABLE [dbo].[tb_symbol_stats_time_windows] (
    [id_time_window] int IDENTITY(1,1) NOT NULL,
    [process_date] date NOT NULL,
    [symbol] varchar(20) NOT NULL,
    [time_window] varchar(11) NOT NULL,
    [window_volume] decimal(18,2) NULL,
    [window_trade_count] int NULL,
    [created_at] datetime2(3) NOT NULL DEFAULT (getdate()),
    CONSTRAINT [PK_tb_symbol_stats_time_windows] PRIMARY KEY ([id_time_window])
);

CREATE INDEX [IX_tb_sstw_date_symbol] ON [dbo].[tb_symbol_stats_time_windows] ([process_date], [symbol]);