CREATE TABLE [dbo].[chart_order_count] (
    [process_date] date NOT NULL,
    [in_order_quantity] bigint NOT NULL,
    [out_order_quantity] bigint NOT NULL,
    CONSTRAINT [PK_chart_order_count] PRIMARY KEY ([process_date])
);