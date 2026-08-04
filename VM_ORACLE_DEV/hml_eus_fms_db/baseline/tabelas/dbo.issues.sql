CREATE TABLE [dbo].[issues] (
    [id] int IDENTITY(1,1) NOT NULL,
    [account] int NOT NULL,
    [date] date NOT NULL,
    [alert_name] varchar(128) NOT NULL,
    [symbol] varchar(32) NOT NULL,
    [party_id] varchar(16) NOT NULL,
    [created_by] varchar(256) NOT NULL,
    [rule] varchar(512) NOT NULL,
    [risk] int NOT NULL,
    [open] bit NOT NULL DEFAULT ((1)),
    [cvm_notification_date] date NULL,
    [bsm_notification_date] date NULL,
    [coaf_notification_date] date NULL,
    [adm_notification_date] date NULL,
    CONSTRAINT [PK_issues] PRIMARY KEY ([id])
);