CREATE TABLE [dbo].[tb_order] (
    [order_key] bigint NOT NULL,
    [order_id] bigint NULL,
    [secondary_order_id] bigint NULL,
    [account] bigint NULL,
    [order_timestamp] datetime2(7) NULL,
    [msg_type] int NULL,
    [party_id] int NULL,
    [price] decimal(17,4) NULL,
    [last_px] decimal(17,4) NULL,
    [quantity] bigint NULL,
    [cumqty] int NULL,
    [lastqty] int NULL,
    [leavesqty] int NULL,
    [side] tinyint NULL,
    [symbol] varchar(30) NULL,
    [exec_type] varchar(32) NULL,
    [ord_status] varchar(16) NULL,
    [process_date] date NULL,
    [book_timestamp] datetime2(7) NULL,
    [book_spread] decimal(17,2) NULL,
    [order_spread] decimal(17,2) NULL,
    [trade_id] bigint NULL,
    [source_id] int NULL,
    [trading_session_sub_id] varchar(16) NULL,
    CONSTRAINT [PK_tb_order] PRIMARY KEY ([order_key])
);

CREATE INDEX [IDX_001] ON [dbo].[tb_order] ([account], [side], [symbol], [exec_type], [book_timestamp]);

CREATE INDEX [IDX_002] ON [dbo].[tb_order] ([exec_type]);

CREATE INDEX [IDX_003] ON [dbo].[tb_order] ([exec_type], [source_id]);