CREATE TABLE [dbo].[sysdiagrams] (
    [name] sysname NOT NULL,
    [principal_id] int NOT NULL,
    [diagram_id] int IDENTITY(1,1) NOT NULL,
    [version] int NULL,
    [definition] varbinary(MAX) NULL,
    CONSTRAINT [PK_sysdiagrams] PRIMARY KEY ([diagram_id])
);