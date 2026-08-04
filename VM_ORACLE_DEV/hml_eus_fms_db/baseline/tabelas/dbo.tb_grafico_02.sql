CREATE TABLE [dbo].[tb_grafico_02] (
    [id] int NOT NULL,
    [data_referencia] date NOT NULL,
    [insercao] int NOT NULL,
    [modificacao] int NOT NULL,
    [trade] int NOT NULL,
    [cancelamento] int NOT NULL,
    [qtd_tb_trade] int NOT NULL,
    [criado_em] datetime NOT NULL DEFAULT (getdate()),
    CONSTRAINT [PK_tb_grafico_02] PRIMARY KEY ([id])
);