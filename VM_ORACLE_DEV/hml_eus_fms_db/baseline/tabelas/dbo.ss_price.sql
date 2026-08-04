CREATE TABLE [dbo].[ss_price] (
    [process_date] datetime2(7) NULL,
    [symbol] varchar(30) NULL,
    [time_sample] datetime2(7) NOT NULL,
    [sample_size] int NOT NULL,
    [price] int NOT NULL
);