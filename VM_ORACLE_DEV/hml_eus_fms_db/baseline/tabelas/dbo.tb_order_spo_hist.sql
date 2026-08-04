CREATE TABLE [dbo].[tb_order_spo_hist] (
    [order_key] bigint NOT NULL,
    [order_id] bigint NULL,
    [secondary_order_id] bigint NULL,
    [account] bigint NULL,
    [order_timestamp] datetime2(7) NULL,
    [msg_type] int NULL,
    [party_id] int NULL,
    [price] varchar(30) NULL,
    [quantity] bigint NULL,
    [side] tinyint NULL,
    [symbol] varchar(30) NULL,
    [exec_type] varchar(32) NULL,
    [ord_status] int NULL,
    [process_date] datetime2(7) NOT NULL,
    [book_timestamp] datetime2(7) NULL,
    [book_spread] decimal(17,2) NULL,
    [order_spread] decimal(17,2) NULL,
    [flag_recurrence] int NULL,
    [flag_cross] int NULL,
    CONSTRAINT [PK_tb_order_spo_hist] PRIMARY KEY ([order_key], [process_date])
);

ALTER TABLE [dbo].[tb_order_spo_hist] ADD CONSTRAINT [FK_tb_order_spo_hist_2] FOREIGN KEY ([account], [symbol], [process_date]) REFERENCES [dbo].[tb_account_spo_hist] ([account], [symbol], [process_date]);