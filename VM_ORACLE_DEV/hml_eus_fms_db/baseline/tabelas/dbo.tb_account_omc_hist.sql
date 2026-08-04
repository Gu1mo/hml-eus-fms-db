CREATE TABLE [dbo].[tb_account_omc_hist] (
    [id_acc] int IDENTITY(1,1) NOT NULL,
    [account] bigint NOT NULL,
    [symbol] varchar(30) NOT NULL,
    [process_date] datetime2(7) NOT NULL,
    CONSTRAINT [PK_tb_account_omc_hist] PRIMARY KEY ([account], [symbol], [process_date])
);