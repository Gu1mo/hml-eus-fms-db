CREATE TABLE [dbo].[UsuarioPortal] (
    [Id] int IDENTITY(1,1) NOT NULL,
    [Usuario] nvarchar(200) NOT NULL,
    [Nome] nvarchar(500) NOT NULL,
    [ChaveSenha] varchar(1024) NULL,
    [Senha] varchar(1024) NULL,
    [Email] nvarchar(200) NOT NULL,
    [Ativo] bit NOT NULL,
    [Administrador] bit NOT NULL,
    [Perfil] varchar(50) NULL,
    [data_ultima_senha] smalldatetime NULL,
    [DATA_EXPIRA_SENHA] smalldatetime NULL,
    [QTD_SENHA_EXPIRADA] int NULL,
    [CODIGO_VERIFICACAO] nvarchar(50) NULL,
    [createdAt] smalldatetime NULL,
    CONSTRAINT [PK_UsuarioPortal] PRIMARY KEY ([Id])
);