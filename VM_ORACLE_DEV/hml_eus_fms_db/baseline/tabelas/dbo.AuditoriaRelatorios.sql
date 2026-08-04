CREATE TABLE [dbo].[AuditoriaRelatorios] (
    [id] int IDENTITY(1,1) NOT NULL,
    [userId] int NULL,
    [data] smalldatetime NULL,
    [idRelatorio] varchar(4000) NULL,
    [apiRoute] varchar(100) NULL,
    CONSTRAINT [PK_AuditoriaRelatorios] PRIMARY KEY ([id])
);