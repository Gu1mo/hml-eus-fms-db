CREATE TABLE [dbo].[tb_entrypoint] (
    [id] int NOT NULL,
    [order_id] bigint NULL,
    [secondary_order_id] bigint NULL,
    [account] bigint NULL,
    [order_timestamp] datetime2(7) NULL,
    [msg_type] varchar(30) NULL,
    [party_id] int NULL,
    [price] decimal(17,4) NULL,
    [last_px] decimal(17,4) NULL,
    [quantity] bigint NULL,
    [cumqty] bigint NULL,
    [lastqty] bigint NULL,
    [leavesqty] bigint NULL,
    [side] tinyint NULL,
    [symbol] varchar(30) NULL,
    [exec_type] varchar(32) NULL,
    [ord_status] varchar(16) NULL,
    [process_date] date NULL,
    [trade_id] bigint NULL,
    [trading_session_sub_id] varchar(16) NULL,
    CONSTRAINT [PK_tb_entrypoint] PRIMARY KEY ([id])
);

CREATE INDEX [id001_tb_entrypoint2] ON [dbo].[tb_entrypoint] ([exec_type]);

CREATE INDEX [id002_tb_entrypoint2] ON [dbo].[tb_entrypoint] ([exec_type], [order_id], [secondary_order_id]);