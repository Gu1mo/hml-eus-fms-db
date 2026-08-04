CREATE TABLE [dbo].[log_ms] (
    [id_log] int IDENTITY(1,1) NOT NULL,
    [process] nvarchar(100) NULL,
    [dt_exec] date NULL,
    [dt_begin] datetime NULL,
    [dt_end] datetime NULL,
    [duration] time(7) NULL,
    [status_description] varchar(2000) NULL,
    [process_date] date NOT NULL,
    CONSTRAINT [PK_log_ms] PRIMARY KEY ([id_log])
);