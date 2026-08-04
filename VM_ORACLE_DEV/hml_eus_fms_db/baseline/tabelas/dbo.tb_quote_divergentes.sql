CREATE TABLE [dbo].[tb_quote_divergentes] (
    [symbol] varchar(30) NULL,
    [symbol_timestamp] date NULL,
    [trade_count] bigint NULL,
    [TOTNEG] float NULL,
    [financial_volume] decimal(17,4) NULL,
    [VOLTOT] float NULL
);