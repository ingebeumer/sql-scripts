/*	SQL Server | maintenance
	Remove duplicate statistics from all user databases
	--Find duplicate statistics in all user databases and then remove overlapping column stats which are also covered by index stats
	--script based on https://logicalreads.wordpress.com/2013/11/14/duplicate-statistics-sql-server/

	Disclaimer: These scripts are provided as is without warranty of any kind, they are not officially Microsoft reviewed and approved.
 
	Unknown date	| Inge van der Zouw-Beumer	| Scripts written and tested. 
	13-09-2017		| Inge van der Zouw-Beumer	| Scripts verified. Any feedback and your perspective is welcome.
	14-03-2022		| Inge van der Zouw-Beumer	| Added some more remarks.

	- Be careful when you drop statistics. Doing so may affect the execution plan chosen by the query optimizer.
	- This is by no means an invitation to disable the Auto Create Statistics database setting, it remains a recommended practice to enable the setting. 
	 
	Having said that, sometimes it can be useful to cleanup duplicate statistics. 
	Over time they were implicitly and quietly auto created to support the queries for the workload at that time, 
	while later an index (with accompanying index statistic) was created. 
	Having duplicate statistics (both column statistics and index statistics) is not optimal for Query Optimizer and Cardinality Estimator. 
	
	All these accumulated statistics are maintained in your statistics maintenance, which is an expensive process.
	Dropping them may cause a temporary performance degradation. It will place some temporary stress on the system as queries are run, 
	Query Optimizer will detect missing statistics and will create them. However when running a representative workload,
	pretty soon all that are necessary are recreated and Query Optimizer and statistics maintenance 
	only need to work with statistics used by current query patterns. All old and now unnecessary statistics ballast is gone.


	-> Please test before you execute any in your production environment
	-> Check for any vendor specific recommendations before executing scripts
	-> Test a possible performance impact on your workload
	-> Run the drop statements outside of business hours
*/

--first part finds all duplicate statistics in all databases
SET NOCOUNT ON
CREATE TABLE ##command (cmd varchar(1024))
SELECT name INTO #databases FROM master.sys.databases sd WHERE database_id > 4 AND state_desc = 'ONLINE';
DECLARE @db AS VARCHAR(100)
SET @db = (SELECT MIN(name) FROM #databases)
WHILE @db IS NOT NULL
BEGIN 
EXEC ('
USE [' + @db + '] 
;WITH autostats (object_id, stats_id, NAME, column_id)
AS (
	SELECT sys.stats.object_id
		, sys.stats.stats_id
		, sys.stats.NAME
		, sys.stats_columns.column_id
	FROM sys.stats
	INNER JOIN sys.stats_columns ON sys.stats.object_id = sys.stats_columns.object_id AND sys.stats.stats_id = sys.stats_columns.stats_id
	WHERE sys.stats.auto_created = 1 AND sys.stats_columns.stats_column_id = 1
	)
INSERT INTO ##command SELECT ''USE [' + @db + '] IF EXISTS (SELECT NAME FROM sys.stats WHERE NAME = N'''''' + autostats.NAME + '''''''' + '' AND object_id = OBJECT_ID(N'''''' + OBJECT_SCHEMA_NAME(sys.stats.object_id) + ''.'' + OBJECT_NAME(sys.stats.object_id) + '''''')) BEGIN DROP STATISTICS ['' + OBJECT_SCHEMA_NAME(sys.stats.object_id) + ''].['' + OBJECT_NAME(sys.stats.object_id) + ''].['' + autostats.NAME + ''] END;'' AS cmd
FROM sys.stats
INNER JOIN sys.stats_columns ON sys.stats.object_id = sys.stats_columns.object_id AND sys.stats.stats_id = sys.stats_columns.stats_id
INNER JOIN autostats ON sys.stats_columns.object_id = autostats.object_id AND sys.stats_columns.column_id = autostats.column_id
INNER JOIN sys.columns ON sys.stats.object_id = sys.columns.object_id AND sys.stats_columns.column_id = sys.columns.column_id
WHERE sys.stats.auto_created = 0 
	AND sys.stats_columns.stats_column_id = 1
	AND sys.stats_columns.stats_id <> autostats.stats_id
	AND OBJECTPROPERTY(sys.stats.object_id, ''IsMsShipped'') = 0;
 ')
SET @db = (SELECT MIN(name) FROM #databases WHERE name > @db)
END
GO
 
--second part PRINTs or EXECs the command to remove overlapping column stats which are also covered by index stats
DECLARE @cmd varchar(1024)
SET @cmd = (SELECT MIN(cmd) FROM ##command)
WHILE @cmd IS NOT NULL
BEGIN 
PRINT @cmd
-- SSMS might not show the full command, adjust Tools - Options - Query Results - SQL Server - Results to Text - Maximum number of characters displayed in each column
-- reopen script in new query window after adjusting the SSMS settings
--EXEC (@cmd)
SET @cmd = (SELECT MIN(cmd) FROM ##command WHERE cmd > @cmd)
END
 
--cleanup
DROP TABLE #databases;
DROP TABLE ##command;
 
 /*
--the original select to find duplicate statistics
WITH autostats (object_id, stats_id, NAME, column_id)
AS (
	SELECT sys.stats.object_id
		, sys.stats.stats_id
		, sys.stats.NAME
		, sys.stats_columns.column_id
	FROM sys.stats
	INNER JOIN sys.stats_columns ON sys.stats.object_id = sys.stats_columns.object_id
		AND sys.stats.stats_id = sys.stats_columns.stats_id
	WHERE sys.stats.auto_created = 1
		AND sys.stats_columns.stats_column_id = 1
	)
SELECT DISTINCT OBJECT_SCHEMA_NAME(sys.stats.object_id) AS [Schema]
	, OBJECT_NAME(sys.stats.object_id) AS [Table]
	, sys.columns.NAME AS [Column]
	, sys.stats.NAME AS [Overlapped]
	, autostats.NAME AS [Overlapping]
	, 'IF EXISTS (SELECT NAME FROM sys.stats WHERE NAME = N''' + autostats.NAME + '''' + ' AND object_id = OBJECT_ID(N''' + OBJECT_SCHEMA_NAME(sys.stats.object_id) + '.' + OBJECT_NAME(sys.stats.object_id) + ''')) BEGIN DROP STATISTICS [' + OBJECT_SCHEMA_NAME(sys.stats.object_id) + '].[' + OBJECT_NAME(sys.stats.object_id) + '].[' + autostats.NAME + '] END;' AS drop_stats
	, 'CREATE STATISTICS [' + autostats.NAME + '] ON ' + OBJECT_SCHEMA_NAME(sys.stats.object_id) + '.' + OBJECT_NAME(sys.stats.object_id) + ' ([' + sys.columns.NAME + ']);' AS create_stats
FROM sys.stats
INNER JOIN sys.stats_columns ON sys.stats.object_id = sys.stats_columns.object_id
	AND sys.stats.stats_id = sys.stats_columns.stats_id
INNER JOIN autostats ON sys.stats_columns.object_id = autostats.object_id
	AND sys.stats_columns.column_id = autostats.column_id
INNER JOIN sys.columns ON sys.stats.object_id = sys.columns.object_id
	AND sys.stats_columns.column_id = sys.columns.column_id
WHERE sys.stats.auto_created = 0
	AND sys.stats_columns.stats_column_id = 1
	AND sys.stats_columns.stats_id <> autostats.stats_id
	AND OBJECTPROPERTY(sys.stats.object_id, 'IsMsShipped') = 0;
*/
