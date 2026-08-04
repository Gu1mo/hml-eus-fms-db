CREATE TABLE [dbo].[tb_trade_duplicados] (
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
    [process_date] date NULL
);