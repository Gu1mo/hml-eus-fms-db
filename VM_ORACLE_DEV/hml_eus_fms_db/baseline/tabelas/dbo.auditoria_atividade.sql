CREATE TABLE [dbo].[auditoria_atividade] (
    [id] int IDENTITY(1,1) NOT NULL,
    [data_hora] datetime2(7) NOT NULL,
    [email] nvarchar(255) NOT NULL,
    [descricao] nvarchar(500) NOT NULL,
    [status_log] bit NOT NULL,
    [status_erro] nvarchar(500) NOT NULL,
    [tipo_usuario] nvarchar(50) NOT NULL,
    [ip_usuario] nvarchar(100) NOT NULL,
    [user_agent] nvarchar(500) NOT NULL,
    CONSTRAINT [PK_auditoria_atividade] PRIMARY KEY ([id])
);