CREATE TABLE [dbo].[ss_peak] (
    [process_date] datetime2(7) NULL,
    [symbol] varchar(30) NULL,
    [peak_price] numeric(18,2) NOT NULL,
    [peak_time] datetime2(7) NOT NULL,
    [start_growth] datetime2(7) NOT NULL,
    [end_peak] datetime2(7) NOT NULL,
    [end_decline] datetime2(7) NOT NULL
);