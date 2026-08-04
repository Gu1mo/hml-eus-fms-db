CREATE TABLE [dbo].[qs_message_volume] (
    [process_date] datetime2(7) NULL,
    [symbol] varchar(30) NULL,
    [time_sample] datetime2(7) NOT NULL,
    [sample_size] int NOT NULL,
    [message_count] int NOT NULL
);