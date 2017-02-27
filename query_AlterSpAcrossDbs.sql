DECLARE @schema SYSNAME
	,@spname SYSNAME
	,@sql NVARCHAR(MAX)

SELECT @schema = 'dbo'
	,@spname = 'SPNAMEHERE'

SET @sql = '
ALTER PROCEDURE ' + QUOTENAME(@schema) + '.' + QUOTENAME(@spname) + '
AS
BEGIN
END
'


IF OBJECT_ID('tempdb..#databases') IS NOT NULL DROP TABLE #databases
SELECT name
INTO #databases
FROM sys.databases
WHERE state = 0
	AND name NOT IN (
		'master'
		,'model'
		,'tempdb'
		,'msdb'
		)

DECLARE @dbname SYSNAME
	,@executesql NVARCHAR(MAX)

WHILE EXISTS (SELECT * FROM #databases)
BEGIN
    SELECT TOP (1) @dbname = name FROM #databases

    IF OBJECT_ID(QUOTENAME(@dbname) + '.' + QUOTENAME(@schema) + '.' + QUOTENAME(@spname)) IS NOT NULL
    BEGIN
		PRINT @dbname
    
		SET @executesql = 'EXEC ' + QUOTENAME(@dbname) + '.[dbo].[sp_executesql] @sql';

		EXEC [dbo].[sp_executesql] @executesql, N'@sql NVARCHAR(MAX)', @sql;
	END

	DELETE #databases WHERE name = @dbname
END
