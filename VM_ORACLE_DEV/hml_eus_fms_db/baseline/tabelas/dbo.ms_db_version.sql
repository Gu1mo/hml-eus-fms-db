CREATE TABLE [dbo].[ms_db_version] (
    [id] int IDENTITY(1,1) NOT NULL,
    [db_version] varchar(30) NULL,
    [update_date] date NULL
);