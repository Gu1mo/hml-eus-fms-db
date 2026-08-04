CREATE TABLE [dbo].[qs_hft_account] (
    [account] varchar(64) NOT NULL,
    [process_date] datetime2(7) NULL,
    [symbol] varchar(30) NULL,
    [total_orders] int NOT NULL,
    [avg_orders] numeric(18,2) NOT NULL,
    [stddev_orders] numeric(18,2) NOT NULL
);