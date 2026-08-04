CREATE TABLE [dbo].[tb_symbol_osc_hist] (
    [symbol] varchar(30) NOT NULL,
    [financial_volume] decimal(17,2) NULL,
    [trade_count] bigint NULL,
    [ratio] decimal(17,2) NULL,
    [process_date] datetime2(7) NOT NULL,
    CONSTRAINT [PK_tb_symbol_osc_hist] PRIMARY KEY ([symbol], [process_date])
);