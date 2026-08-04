CREATE TABLE [dbo].[tb_client_counterparty] (
    [id] int IDENTITY(1,1) NOT NULL,
    [process_date] date NOT NULL,
    [account] varchar(50) NOT NULL,
    [symbol] varchar(20) NOT NULL,
    [counterparty] varchar(100) NOT NULL,
    [volume] decimal(18,4) NOT NULL DEFAULT ((0)),
    [created_at] datetime2(7) NOT NULL DEFAULT (getdate()),
    CONSTRAINT [PK_tb_client_counterparty] PRIMARY KEY ([id])
);

ALTER TABLE [dbo].[tb_client_counterparty] ADD CONSTRAINT [FK_client_counterparty_profile] FOREIGN KEY ([process_date], [account], [symbol]) REFERENCES [dbo].[tb_client_daily_profile] ([process_date], [account], [symbol]);