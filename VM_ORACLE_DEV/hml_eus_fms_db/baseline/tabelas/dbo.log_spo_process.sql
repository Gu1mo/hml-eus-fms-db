CREATE TABLE [dbo].[log_spo_process] (
    [id_log] bigint IDENTITY(1,1) NOT NULL,
    [order_key] bigint NULL,
    [price] decimal(17,2) NULL,
    [side] tinyint NULL,
    [account] bigint NULL,
    [symbol] varchar(30) NULL,
    [book_timestamp] datetime2(7) NULL,
    [secondary_order_id] bigint NULL,
    [process_date] date NULL,
    [flag_spo] bit NULL,
    [flag_description] varchar(200) NULL
);