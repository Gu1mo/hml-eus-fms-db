CREATE TABLE [dbo].[ss_beneficiary] (
    [id] int IDENTITY(1,1) NOT NULL,
    [process_date] datetime2(7) NULL,
    [symbol] varchar(30) NULL,
    [beneficiary_account] varchar(64) NOT NULL,
    [diff] numeric(18,2) NOT NULL,
    [recurrent_alert] bit NOT NULL,
    CONSTRAINT [PK_ss_beneficiary] PRIMARY KEY ([id])
);