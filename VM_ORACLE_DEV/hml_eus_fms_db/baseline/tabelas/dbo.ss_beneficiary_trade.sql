CREATE TABLE [dbo].[ss_beneficiary_trade] (
    [beneficiary_id] int NOT NULL,
    [trade_time] datetime2(7) NOT NULL,
    [price] numeric(18,2) NOT NULL,
    [quantity] bigint NOT NULL,
    [cross_trade] bit NULL
);

ALTER TABLE [dbo].[ss_beneficiary_trade] ADD CONSTRAINT [FK__ss_benefi__benef__36470DEF] FOREIGN KEY ([beneficiary_id]) REFERENCES [dbo].[ss_beneficiary] ([id]);