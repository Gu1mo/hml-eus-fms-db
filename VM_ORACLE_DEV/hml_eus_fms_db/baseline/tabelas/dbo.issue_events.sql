CREATE TABLE [dbo].[issue_events] (
    [id] int IDENTITY(1,1) NOT NULL,
    [issue_id] int NOT NULL,
    [analysis] varchar(MAX) NOT NULL,
    [date] date NOT NULL,
    [created_by] varchar(256) NOT NULL,
    [conclusion] nvarchar(MAX) NULL,
    [additional_info] text NULL,
    CONSTRAINT [PK_issue_events] PRIMARY KEY ([id])
);

ALTER TABLE [dbo].[issue_events] ADD CONSTRAINT [FK_IssueEvents_Issues] FOREIGN KEY ([issue_id]) REFERENCES [dbo].[issues] ([id]);