CREATE procedure [dbo].[usp_report_monitoring]
as
DECLARE @html NVARCHAR(MAX), @client nVARCHAR(100) = 'Toro', @database nvarchar(50);
set @database=  DB_NAME();

SET @html = N'<html><head><link href="https://fonts.googleapis.com/css?family=Roboto:400,100,300,700" rel="stylesheet" type="text/css"><link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css" rel="stylesheet">
<style>body {font-family: ''Roboto'', Arial, sans-serif;} table {width: 100%; max-width: 800px; border-collapse: collapse;} th, td {padding: 8px; text-align: left; border: 1px solid #eee; white-space: nowrap;} th {background-color: #f2f2f2; width: auto;} .completed {background-color: #82dd55;} .started {background-color: #edb95e;} .error {background-color: #e23636;} </style></head><body><h2><i class="fas fa-network-wired"></i>
' + @client + ' - Fira Market Surveillance</h2><i class="fas fa-database"></i> '+@database+'<br><br><table><tr><th>Process</th><th>Date of Execution</th><th>Process Date</th><th>Start Time</th><th>End Time</th><th>Duration</th><th>Status</th></tr>';

SELECT @html = @html + N'<tr class="' 
                        + CASE 
                            WHEN a.status_description = 'Completed' THEN 'completed"><td>' + a.process + N'</td><td>'
                            WHEN a.status_description = 'Started' THEN 'started"><td>' + a.process + N'</td><td>'
                            ELSE 'error"><td>' + a.process + N'</td><td>'
                          END 
                        + CONVERT(NVARCHAR, a.dt_exec, 121) + N'</td><td>'
						+ CONVERT(NVARCHAR, a.process_date, 121) + N'</td><td>'
                        + CONVERT(VARCHAR(5), a.dt_begin, 108) + N'</td><td>'  -- HH:MM format for Start Time
                        + isnull(CONVERT(VARCHAR(5), a.dt_end, 108),'-') + N'</td><td>'  -- HH:MM format for End Time
                        + isnull(CONVERT(VARCHAR, a.duration, 108),'-') + N'</td><td>'  -- HH:MM:SS format for Duration
                        + CASE 
                            WHEN a.status_description = 'Completed' THEN NCHAR(0x2705) + ' Completed' 
                            WHEN a.status_description = 'Started' THEN NCHAR(0x26A0) + ' Running...'  -- ⚠️ (Warning)
                            ELSE NCHAR(0x274C) + ' Error'  -- ❌ (Cross Mark)
                          END + N'</td></tr>'
FROM log_ms a
INNER JOIN (SELECT MAX(id_log) id_log, process
            FROM log_ms

            GROUP BY process) b
ON a.id_log = b.id_log;

SET @html = @html + N'</table></body></html>';

truncate table log_monitoring_report
insert into log_monitoring_report
select @html as query;