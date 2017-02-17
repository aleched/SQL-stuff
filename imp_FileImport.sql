ALTER PROCEDURE [dbo].[imp_FileImport] (
	@FilePath VARCHAR(MAX)
	,@FileType VARCHAR(5)
	,@HeaderRowCount BIT = 1
	,@SheetName VARCHAR(100) = NULL
	,@ColumnSeparator CHAR(1) = NULL
	,@ColumnHeaderList VARCHAR(MAX) = NULL
	)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ErrorMessage VARCHAR(1000)
		,@SQL VARCHAR(MAX)

	-------------------------
	--	Error Checking
	-------------------------
	IF (@FileType NOT IN ('excel','csv','txt'))
		RAISERROR ('ImportFrom file type input is invalid.',16,1)

	IF (@HeaderRowCount NOT IN (0,1))
		RAISERROR ('HeaderRowCount input is invalid.',16,1)


	IF (@FileType = 'csv' AND @ColumnSeparator <> ',')
		RAISERROR ('Invalid ColumnSeparator selected for ImportFrom file type of CSV.',16,1)

	SET @SQL = '
				IF EXISTS (
						SELECT RIGHT(BulkColumn,1)
						FROM OPENROWSET(BULK ''' + @FilePath + ''', SINGLE_CLOB) myfile
						WHERE RIGHT(BulkColumn,1) =  ''	''
						)
				BEGIN
					RAISERROR (''The file format is incorrect. A closing new line is missing. Please open the file in  Notepad, press Enter at the end of the file, save the file, and try processing again.'', 16, 1)
				END
				'

	EXEC (@SQL)

	-------------------------
	--	Set Variables, Create Tables
	-------------------------
	SET @SQL = 'CREATE TABLE ##ImportExportTemp(' + REPLACE(@ColumnHeaderList, ',', ' VARCHAR(500), ') + ' VARCHAR(500)' + ')'

	PRINT @SQL

	EXEC (@SQL)

	-------------------------
	--	Bulk Insert
	-------------------------
	IF (@FileType = 'excel')
	BEGIN
		SET @SQL = '
				INSERT ##ImportExportTemp
				SELECT *
				FROM OPENROWSET(''Microsoft.Jet.OLEDB.4.0'',''Excel 8.0
							;Database=' + @FilePath + '
							;HDR=' + CASE @HeaderRowCount WHEN 0 THEN 'No' ELSE 'Yes' END + '
							;IMEX=2'',' + @SheetName + '$ )
				'
	END
	ELSE IF (@FileType = 'txt')
	BEGIN
		SET @SQL = '
				BULK INSERT ##ImportExportTemp
				FROM ''' + @FilePath + '''
				WITH (FIELDTERMINATOR = ''' + @ColumnSeparator + ''',FIRSTROW = ' + CONVERT(CHAR(1), @HeaderRowCount + 1) + ')
				'
	END
	ELSE IF (@FileType = 'csv')
	BEGIN
		CREATE TABLE #rmComma (data VARCHAR(MAX))

		SET @SQL = '
				BULK INSERT #rmComma
				FROM ''' + @FilePath + '''
				WITH (FIRSTROW = ' + CONVERT(CHAR(1), @HeaderRowCount + 1) + ')

				ALTER TABLE #rmComma ADD id INT IDENTITY
				'

		PRINT @SQL

		EXEC (@SQL)

		SET @SQL = '
				;WITH rmCommaCTEp1 (
					depth
					,id
					,data
					) AS (
						SELECT 1
							,id
							,STUFF(data
									,ISNULL(NULLIF(CHARINDEX(''"'',data),0),1)
									,ISNULL(NULLIF(CHARINDEX(''"'',data,CHARINDEX(''"'',data)+1),0)-CHARINDEX(''"'',data)+1,0)
									,REPLACE(SUBSTRING(data
												,CHARINDEX(''"'',data)+1
												,ISNULL(NULLIF(CHARINDEX(''"'',data,CHARINDEX(''"'',data)+1),0)-CHARINDEX(''"'',data)-1,0)
												),'','',''&comma;'')
									)
						FROM #rmComma
						UNION ALL
						SELECT depth+1
							,id
							,STUFF(data
									,ISNULL(NULLIF(CHARINDEX(''"'',data),0),1)
									,ISNULL(NULLIF(CHARINDEX(''"'',data,CHARINDEX(''"'',data)+1),0)-CHARINDEX(''"'',data)+1,0)
									,REPLACE(SUBSTRING(data
												,CHARINDEX(''"'',data)+1
												,ISNULL(NULLIF(CHARINDEX(''"'',data,CHARINDEX(''"'',data)+1),0)-CHARINDEX(''"'',data)-1,0)
												),'','',''&comma;'')
									)
						FROM rmCommaCTEp1
						WHERE CHARINDEX(''"'',data,CHARINDEX(''"'',data)+1) > 0
						)
				,rmCommaCTEp2 (
					revdepth
					,id
					,data
					) AS (
						SELECT ROW_NUMBER() OVER(PARTITION BY id ORDER BY depth DESC)
							,id
							,data
						FROM rmCommaCTEp1
						)
				,rmCommaCTEp3 (
					id
					,colheader
					,header
					,coldata
					,data
					) AS (
						SELECT id
							,LEFT(''' + @ColumnHeaderList + ''',ISNULL(NULLIF(CHARINDEX('','',''' + @ColumnHeaderList + '''),0)-1,LEN(''' + @ColumnHeaderList + ''')))
							,RIGHT(''' + @ColumnHeaderList + ''',LEN(''' + @ColumnHeaderList + ''') - ISNULL(NULLIF(CHARINDEX('','',''' + @ColumnHeaderList + '''),0),LEN(''' + @ColumnHeaderList + ''')))
							,LEFT(data,ISNULL(NULLIF(CHARINDEX('','',data),0)-1,1))
							,RIGHT(data,LEN(data) - ISNULL(NULLIF(CHARINDEX('','',data),0),0))
						FROM rmCommaCTEp2
						WHERE revdepth = 1
						UNION ALL
						SELECT id
							,LEFT(header,ISNULL(NULLIF(CHARINDEX('','',header),0)-1,LEN(header)))
							,RIGHT(header,LEN(header) - ISNULL(NULLIF(CHARINDEX('','',header),0),LEN(header)))
							,LEFT(data,ISNULL(NULLIF(CHARINDEX('','',data),0)-1,LEN(data)))
							,RIGHT(data,LEN(data) - ISNULL(NULLIF(CHARINDEX('','',data),0),LEN(data)))
						FROM rmCommaCTEp3
						WHERE LEN(colheader) > 0
						)
				INSERT ##ImportExportTemp
				SELECT ' + @ColumnHeaderList + '
				FROM (
					SELECT id
						,colheader
						,REPLACE(coldata,''&comma;'','','') AS coldata
					FROM rmCommaCTEp3
					WHERE LEN(colheader) > 0
					) AS cte
				PIVOT (
					MAX(coldata)
					FOR	colheader IN (' + @ColumnHeaderList + ')
					) AS pvt
				'
	END

	PRINT @SQL

	EXEC (@SQL)

	SELECT *
	FROM ##ImportExportTemp

	DROP TABLE ##ImportExportTemp
END
