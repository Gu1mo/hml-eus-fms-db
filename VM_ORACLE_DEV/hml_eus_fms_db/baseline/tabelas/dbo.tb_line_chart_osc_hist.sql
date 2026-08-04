CREATE TABLE [dbo].[tb_line_chart_osc_hist] (
    [id_lc] int IDENTITY(1,1) NOT NULL,
    [symbol] varchar(30) NOT NULL,
    [resampled_time] time(7) NOT NULL,
    [close_amplitude] decimal(17,2) NULL,
    [open_amplitude] decimal(17,2) NULL,
    [previous_price_amplitude] decimal(17,2) NULL,
    [price] decimal(17,2) NULL,
    [process_date] datetime2(7) NOT NULL,
    CONSTRAINT [PK_tb_line_chart_osc_hist] PRIMARY KEY ([symbol], [resampled_time], [process_date])
);