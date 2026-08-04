CREATE TABLE [dbo].[qs_high_otr_account] (
    [account] varchar(64) NOT NULL,
    [process_date] datetime2(7) NULL,
    [symbol] varchar(30) NULL,
    [otr] numeric(18,2) NOT NULL,
    [avg_otr] numeric(18,2) NOT NULL,
    [stddev_otr] numeric(18,2) NOT NULL
);