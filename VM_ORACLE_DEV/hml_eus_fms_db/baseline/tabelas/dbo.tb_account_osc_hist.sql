CREATE TABLE [dbo].[tb_account_osc_hist] (
    [id_acc] int IDENTITY(1,1) NOT NULL,
    [account] bigint NOT NULL,
    [symbol] varchar(30) NOT NULL,
    [process_date] datetime2(7) NOT NULL,
    CONSTRAINT [PK_tb_account_osc_hist] PRIMARY KEY ([account], [symbol], [process_date])
);

ALTER TABLE [dbo].[tb_account_osc_hist] ADD CONSTRAINT [FK_tb_account_osc_hist_2] FOREIGN KEY ([symbol], [process_date]) REFERENCES [dbo].[tb_symbol_osc_hist] ([symbol], [process_date]);