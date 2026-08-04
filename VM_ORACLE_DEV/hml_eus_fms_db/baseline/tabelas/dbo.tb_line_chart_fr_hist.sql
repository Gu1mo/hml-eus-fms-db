CREATE TABLE [dbo].[tb_line_chart_fr_hist] (
    [id_line] int IDENTITY(1,1) NOT NULL,
    [symbol] varchar(30) NOT NULL,
    [resampled_time] time(7) NOT NULL,
    [avg_quantity] bigint NULL,
    [line_type] int NOT NULL,
    [process_date] date NOT NULL,
    CONSTRAINT [PK_tb_line_chart_fr_hist] PRIMARY KEY ([symbol], [resampled_time], [line_type], [process_date])
);