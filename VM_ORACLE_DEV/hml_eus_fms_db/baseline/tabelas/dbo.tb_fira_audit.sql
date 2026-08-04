CREATE TABLE [dbo].[tb_fira_audit] (
    [ID] int IDENTITY(0,1) NOT NULL,
    [EventDate] datetime NOT NULL DEFAULT (getdate()),
    [EventType] nvarchar(64) NULL,
    [EventDDL] nvarchar(MAX) NULL,
    [EventXML] xml NULL,
    [DatabaseName] nvarchar(255) NULL,
    [SchemaName] nvarchar(255) NULL,
    [ObjectName] nvarchar(255) NULL,
    [HostName] varchar(64) NULL,
    [IPAddress] varchar(48) NULL,
    [ProgramName] nvarchar(255) NULL,
    [LoginName] nvarchar(255) NULL,
    [IN_EMAIL] nchar(16) NULL,
    CONSTRAINT [PK_tb_fira_audit] PRIMARY KEY ([ID])
);