CREATE TABLE [dbo].[tb_calendar] (
    [calendar_id] int IDENTITY(1,1) NOT NULL,
    [reference_date] date NULL,
    [day_of_month] tinyint NULL,
    [month_number] tinyint NULL,
    [year_number] int NULL,
    [previous_date] date NULL,
    [next_date] date NULL,
    [end_of_month_date] date NULL,
    [start_of_month_date] date NULL,
    [previous_workday_date] date NULL,
    [next_workday_date] date NULL,
    [weekday_name] nvarchar(30) NULL,
    [is_workday] bit NULL,
    [is_holiday] bit NULL,
    [week_of_year] int NULL
);