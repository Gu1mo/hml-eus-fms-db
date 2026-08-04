CREATE TABLE [dbo].[ss_short_seller] (
    [process_date] datetime2(7) NULL,
    [symbol] varchar(30) NULL,
    [short_seller_account] varchar(64) NOT NULL,
    [buy] bigint NOT NULL,
    [sell] bigint NOT NULL
);