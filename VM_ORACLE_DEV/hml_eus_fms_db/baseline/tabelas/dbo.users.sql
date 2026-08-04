CREATE TABLE [dbo].[users] (
    [id] int IDENTITY(1,1) NOT NULL,
    [email] nvarchar(255) NOT NULL,
    [permission] nvarchar(20) NOT NULL DEFAULT ('default'),
    [blocked] bit NOT NULL DEFAULT ((0)),
    [created_at] datetime2(7) NOT NULL DEFAULT (sysutcdatetime()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK_users] PRIMARY KEY ([id]),
    CONSTRAINT [CK_users_permission] CHECK ([permission]='default' OR [permission]='admin')
);