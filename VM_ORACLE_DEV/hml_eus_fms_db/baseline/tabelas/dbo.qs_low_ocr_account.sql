CREATE TABLE [dbo].[qs_low_ocr_account] (
    [account] varchar(64) NOT NULL,
    [process_date] datetime2(7) NULL,
    [symbol] varchar(30) NULL,
    [ocr] numeric(18,2) NOT NULL,
    [avg_ocr] numeric(18,2) NOT NULL,
    [stddev_ocr] numeric(18,2) NOT NULL
);