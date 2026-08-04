CREATE TABLE [dbo].[tb_trade] (
    [id_trade] bigint NOT NULL,
    [msg_time] time(7) NULL,
    [header] char(1) NULL,
    [symbol] varchar(30) NULL,
    [task] char(1) NULL,
    [price] decimal(17,2) NULL,
    [quantity] bigint NULL,
    [trade_time] time(7) NULL,
    [broker_buy] int NULL,
    [broker_sell] int NULL,
    [trade_id] bigint NULL,
    [direct] int NULL,
    [aggressor] char(1) NULL,
    [process_date] date NULL,
    CONSTRAINT [PK_tb_trade] PRIMARY KEY ([id_trade])
);

CREATE INDEX [IDX_001] ON [dbo].[tb_trade] ([symbol], [trade_time]);

CREATE INDEX [IDX_002] ON [dbo].[tb_trade] ([task]);

CREATE INDEX [IDX_003] ON [dbo].[tb_trade] ([symbol], [trade_time]);

CREATE INDEX [IDX_004] ON [dbo].[tb_trade] ([symbol]);

CREATE INDEX [IDX_005] ON [dbo].[tb_trade] ([symbol], [quantity]);

CREATE INDEX [IDX_006] ON [dbo].[tb_trade] ([symbol], [task]);

CREATE INDEX [IDX_007] ON [dbo].[tb_trade] ([task], [symbol]);

CREATE INDEX [IDX_10] ON [dbo].[tb_trade] ([symbol], [trade_id]);