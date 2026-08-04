CREATE TABLE [dbo].[issue_event_drafts] (
    [id] int IDENTITY(1,1) NOT NULL,
    [issue_id] int NOT NULL,
    [analysis] nvarchar(MAX) NOT NULL,
    [risk] int NOT NULL,
    [open] bit NOT NULL,
    [cvm_notification_date] date NULL,
    [bsm_notification_date] date NULL,
    [coaf_notification_date] date NULL,
    [adm_notification_date] date NULL,
    [created_by] nvarchar(255) NOT NULL,
    [created_at] datetime2(7) NOT NULL DEFAULT (getdate()),
    [updated_at] datetime2(7) NOT NULL DEFAULT (getdate()),
    [conclusion] nvarchar(MAX) NULL,
    [additional_info] text NULL,
    CONSTRAINT [PK_issue_event_drafts] PRIMARY KEY ([id])
);

ALTER TABLE [dbo].[issue_event_drafts] ADD CONSTRAINT [FK_issue_event_drafts_issue] FOREIGN KEY ([issue_id]) REFERENCES [dbo].[issues] ([id]);