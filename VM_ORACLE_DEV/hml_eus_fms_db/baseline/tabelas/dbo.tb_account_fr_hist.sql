CREATE TABLE [dbo].[tb_account_fr_hist] (
    [id_acc] int IDENTITY(1,1) NOT NULL,
    [account] bigint NOT NULL,
    [symbol] varchar(30) NOT NULL,
    [process_date] date NOT NULL,
    CONSTRAINT [PK_tb_account_fr_hist] PRIMARY KEY ([account], [symbol], [process_date])
);