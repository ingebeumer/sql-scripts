/*	SQL Server | maintenance
	Cleanup all auto created statistics from all user databases
	-- script based on https://docs.microsoft.com/en-us/archive/blogs/mvpawardprogram/sql-server-auto-statistics-cleanup

	Disclaimer: These scripts are provided as is without warranty of any kind, they are not officially Microsoft reviewed and approved.
 
	Unknown date	| Inge van der Zouw-Beumer	| Scripts written and tested. 	
	13-09-2017		| Inge van der Zouw-Beumer	| Scripts verified. Any feedback and your perspective is welcome.
	02-11-2021		| Inge van der Zouw-Beumer	| Added some more remarks.

	- Be careful when you drop statistics. Doing so may affect the execution plan chosen by the query optimizer.
	- This is by no means an invitation to disable the Auto Create Statistics database setting, it remains a recommended practice to enable the setting. 
	 
	Having said that, sometimes it can be useful to cleanup auto created statistics. 
	Over time they were implicitly and quietly auto created to support the queries for the workload at that time, 
	and may no longer be useful for the current workload as reports, software, business logic, and queries have changed. 
	They may even have been created for test or troubleshooting queries that were issued once many years ago.
	Also you may have duplicate statistics as first it was auto created and later an index (with accompanying index statistic) was created. 
	
	All these accumulated statistics are maintained in your statistics maintenance, which is an expensive process.
	Dropping them may cause a temporary performance degradation. It will place some temporary stress on the system as queries are run, 
	Query Optimizer will detect missing statistics and will create them. However when running a representative workload,
	pretty soon all that are necessary are recreated and Query Optimizer and statistics maintenance 
	only need to work with statistics used by current query patterns. All old and now unnecessary statistics ballast is gone.

	-> Please test before you execute any in your production environment
	-> Check for any vendor specific recommendations before executing scripts
	-> Test a possible performance impact on your workload of dropping all auto created column statistics
	-> Run the drop statements outside of business hours
*/
  
-- Please execute script step by step.
USE [master];
GO
SET NOCOUNT ON;
-- Step 1
-- Table to hold all auto stats and their DROP statements
CREATE TABLE #commands (
	Database_Name SYSNAME
	, Table_Name SYSNAME
	, Stats_Name SYSNAME
	, cmd NVARCHAR(4000)
	, CONSTRAINT PK_#commands PRIMARY KEY CLUSTERED (
		Database_Name
		, Table_Name
		, Stats_Name
		)
	);

-- A cursor to browse all user databases
DECLARE Databases CURSOR FOR
SELECT [name] FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE';

DECLARE @Database_Name SYSNAME, @cmd NVARCHAR(4000);

OPEN Databases;

FETCH NEXT FROM Databases INTO @Database_Name;

WHILE @@FETCH_STATUS = 0
BEGIN
	-- Create all DROP statements for the database
	SET @cmd = 'SELECT N''' + @Database_Name + ''', so.name, ss.name, N''IF EXISTS (SELECT name FROM sys.stats WHERE name = '''''' + ss.name + '''''' AND object_id = OBJECT_ID('''''' + ssc.name + ''.'' + so.name + '''''')) BEGIN DROP STATISTICS ['' + ssc.name +'']'' +''.['' + so.name +'']'' + ''.['' + ss.name + ''] END;''
				FROM [' + @Database_Name + '].sys.stats AS ss
				INNER JOIN [' + @Database_Name + '].sys.objects AS so ON ss.[object_id] = so.[object_id]
				INNER JOIN [' + @Database_Name + '].sys.schemas AS ssc ON so.schema_id = ssc.schema_id
				WHERE ss.auto_created = 1 AND so.is_ms_shipped = 0 -- auto created
				--WHERE (ss.auto_created = 0 AND ss.user_created = 1) AND so.is_ms_shipped = 0 -- user created
			';

	--SELECT @cmd -- DEBUG
	-- Execute and store in temp table
	INSERT INTO #commands
	EXECUTE (@cmd);

	-- Next Database
	FETCH NEXT
	FROM Databases
	INTO @Database_Name;
END;
GO

--Step 2
-- Switch query results output to text by clicking Ctrl + T or from the Query menu, select "Results to" and "Text"
-- SSMS might not show the full command, adjust Tools - Options - Query Results - SQL Server - Results to Text - Maximum number of characters displayed in each column
-- reopen script in new query window after adjusting the SSMS settings
-- generate drop statatistics statements
WITH Ordered_Cmd
AS
	-- Add an ordering column to the rows to mark database context
	(SELECT ROW_NUMBER() OVER (PARTITION BY Database_Name ORDER BY Database_Name, Table_Name, Stats_Name) AS Row_Num, * FROM #commands)
SELECT CASE 
		WHEN Row_Num = 1 -- Add the USE statement before the first row for the database
		THEN REPLICATE(N'-', 50) + NCHAR(10) + NCHAR(13) + N'USE [' + Database_Name + '];' + NCHAR(10) + NCHAR(13)
		ELSE ''
		END + cmd
FROM Ordered_Cmd
ORDER BY Database_Name, Table_Name, Stats_Name;

--Step 3
!!--manually execute the statements generated in the previous step

--Step 4
-- CLEANUP
CLOSE Databases;
DEALLOCATE Databases;
DROP TABLE #commands;
