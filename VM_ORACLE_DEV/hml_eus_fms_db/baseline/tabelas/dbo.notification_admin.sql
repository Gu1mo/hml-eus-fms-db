CREATE TABLE [dbo].[notification_admin] (
    [id] int IDENTITY(1,1) NOT NULL,
    [title] nvarchar(200) NOT NULL,
    [description] nvarchar(2000) NOT NULL,
    [expiry_date] date NOT NULL,
    [created_at] datetime NOT NULL DEFAULT (getdate()),
    CONSTRAINT [PK_notification_admin] PRIMARY KEY ([id])
);