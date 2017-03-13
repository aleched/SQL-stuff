ALTER PROCEDURE [dbo].[util_CreateAuditTrigger] (
	@TableName SYSNAME
	,@ColumnName SYSNAME = NULL
	,@SchemaName SYSNAME = 'dbo'
	,@AuditNameSuffix SYSNAME = '_Audit'
	,@TriggerNamePrefix SYSNAME = 'tr_Audit_'
	,@AutoExec BIT = 0
	,@IncludeUserSQL BIT = 1
	,@TriggerLifespan INT = 30  --days
	,@AuditSizeLimit INT = 1024  --MB
	)
AS
BEGIN
	SET NOCOUNT ON;

	BEGIN TRY

		BEGIN TRANSACTION

		-------------------------
		--	Declare and Initialize Variables
		-------------------------
		DECLARE @inputSchemaName SYSNAME
			,@inputTableName SYSNAME
			,@inputColumnName SYSNAME
			,@AuditName SYSNAME
			,@TriggerName SYSNAME
			,@UserName SYSNAME
			,@crlf NCHAR(2)
			,@t NCHAR(1)

		SELECT @inputSchemaName = @SchemaName
			,@inputTableName = @TableName
			,@inputColumnName = @ColumnName
			,@SchemaName = SCHEMA_NAME(SCHEMA_ID(@SchemaName))
			,@TableName = OBJECT_NAME(OBJECT_ID(@TableName))
			,@ColumnName = COL_NAME(OBJECT_ID(@TableName),COLUMNPROPERTY(OBJECT_ID(@TableName),@ColumnName,'COLUMNID'))
			,@AuditName = @TableName + @AuditNameSuffix
			,@TriggerName = @TriggerNamePrefix + @TableName
			,@UserName = SYSTEM_USER
			,@crlf = CHAR(13)+CHAR(10)
			,@t = CHAR(9)

		SELECT @SchemaName = QUOTENAME(@SchemaName)
			,@TableName = QUOTENAME(@TableName)
			,@ColumnName = QUOTENAME(@ColumnName)
			,@AuditName = QUOTENAME(@AuditName)
			,@TriggerName = QUOTENAME(@TriggerName)


		DECLARE @colNamesTable TABLE (
			Ordinal INT
			,Name SYSNAME
			,DataType SYSNAME
			)

		DECLARE @colNamesString NVARCHAR(MAX)
			,@colNamesStringDT NVARCHAR(MAX)

		DECLARE @pvtQuery NVARCHAR(MAX)
			,@tblCreate1 NVARCHAR(MAX)
			,@tblCreate2 NVARCHAR(MAX)
			,@trgCreate1 NVARCHAR(MAX)
			,@trgCreate2 NVARCHAR(MAX)
			,@trgCreate3 NVARCHAR(MAX)
			,@trgCreate4 NVARCHAR(MAX)
			,@trgCreate5 NVARCHAR(MAX)

		DECLARE @ErrorMessage VARCHAR(5000)

		-------------------------
		--	Error Check
		-------------------------
		IF (@SchemaName IS NULL)
		BEGIN
			SET @ErrorMessage = @crlf + 'The schema name input: ' + @inputSchemaName
					+ @crlf + 'does not exist.  Cannot create trigger.'

			RAISERROR (@ErrorMessage,16,1)
		END

		IF (@TableName IS NULL)
		BEGIN
			SET @ErrorMessage = @crlf + 'The table name input: ' + @inputTableName
					+ @crlf + 'does not exist.  Cannot create trigger.'

			RAISERROR (@ErrorMessage,16,1)
		END

		IF (@ColumnName IS NULL AND @inputColumnName IS NOT NULL)
		BEGIN
			SET @ErrorMessage = @crlf + 'The column name input: ' + @inputColumnName
					+ @crlf + 'does not exist.  Cannot create trigger.'

			RAISERROR (@ErrorMessage,16,1)
		END

		IF (OBJECT_ID(@AuditName) IS NOT NULL)
		BEGIN
			SET @ErrorMessage = @crlf + 'The audit table which would be created: ' + @AuditName
					+ @crlf + 'already exists.  Cannot create trigger.'

			RAISERROR (@ErrorMessage,16,1)
		END

		IF (OBJECT_ID(@TriggerName) IS NOT NULL)
		BEGIN
			SET @ErrorMessage = @crlf + 'The trigger which would be created: ' + @TriggerName
					+ @crlf + 'already exists.  Cannot create trigger.'

			RAISERROR (@ErrorMessage,16,1)
		END

		IF (@AuditNameSuffix IS NULL OR @AuditNameSuffix = '')
		BEGIN
			SET @ErrorMessage = @crlf + 'The AuditNameSuffix must be specified.  Cannot create trigger.'

			RAISERROR (@ErrorMessage,16,1)
		END

		IF (@TriggerNamePrefix IS NULL OR @TriggerNamePrefix = '')
		BEGIN
			SET @ErrorMessage = @crlf + 'The TriggerNamePrefix must be specified.  Cannot create trigger.'

			RAISERROR (@ErrorMessage,16,1)
		END

		IF (@TriggerLifespan <= 0)
		BEGIN
			SET @ErrorMessage = @crlf + 'If a TriggerLifespan is specified, it must be greater than 0.  Cannot create trigger.'

			RAISERROR (@ErrorMessage,16,1)
		END

		IF (@AuditSizeLimit <= 0)
		BEGIN
			SET @ErrorMessage = @crlf + 'If an AuditSizeLimit is specified, it must be greater than 0.  Cannot create trigger.'
			RAISERROR (@ErrorMessage,16,1)
		END

		-------------------------
		--	Generate Pivot Query
		-------------------------
		SELECT @pvtQuery = '/*'
				+ @crlf + 'CROSS APPLY ('
				+ @crlf + @t + 'SELECT AuditDate'
				+ @crlf + @t+@t + ',AuditUser'
				+ @crlf + @t+@t + ',AuditSQLExec'
				+ @crlf + @t+@t + ',ISNULL(DELETED,UPDATED_FROM) AS OldValue'
				+ @crlf + @t+@t + ',ISNULL(INSERTED,UPDATED_TO) AS NewValue'
				+ @crlf + @t + 'FROM ('
				+ @crlf + @t+@t + 'SELECT AuditAction'
				+ @crlf + @t+@t+@t + ',AuditDate'
				+ @crlf + @t+@t+@t + ',AuditUser'
				+ @crlf + @t+@t+@t + ',AuditSQLExec'
				+ @crlf + @t+@t+@t + ',CONVERT(NVARCHAR(MAX),' + @ColumnName + ') AS ' + @ColumnName
				+ @crlf + @t+@t + 'FROM ' + @SchemaName + '.' + @TableName + '_Audit audit'
				+ @crlf + @t+@t + 'WHERE ISNULL(audit.AuditColumns,''' + @inputColumnName + ''') LIKE ''%' + @inputColumnName + '%'''
				+ @crlf + @t+@t+@t + 'AND audit.' + COL_NAME(ic.object_id,ic.column_id) + ' = t.' + COL_NAME(ic.object_id,ic.column_id) + ''
				+ @crlf + @t+@t + ') AS src'
				+ @crlf + @t + 'PIVOT ('
				+ @crlf + @t+@t + 'MAX(' + @ColumnName + ')'
				+ @crlf + @t+@t + 'FOR AuditAction IN (UPDATED_FROM,UPDATED_TO,INSERTED,DELETED)'
				+ @crlf + @t+@t + ') AS pvt'
				+ @crlf + @t + ') AS adt'
				+ @crlf + '*/'
		FROM sys.index_columns ic
		INNER JOIN sys.indexes i ON ic.object_id = i.object_id
			AND ic.index_id = i.index_id
		WHERE i.is_primary_key = 1
			AND	ic.object_id = OBJECT_ID(@TableName)

		-------------------------
		--	Gather Column Names
		-------------------------
		INSERT @colNamesTable (
			Ordinal
			,Name
			,DataType
			)
		SELECT c.column_id
			,QUOTENAME(c.name)
			,UPPER(t.name)	+ CASE
					WHEN t.name IN ('CHAR','NCHAR','VARCHAR','NVARCHAR','VARBINARY','NVARBINARY')
						THEN '(' + REPLACE(CONVERT(NVARCHAR(10),c.max_length),'-1','MAX') + ')'
					WHEN t.name IN ('DECIMAL','NUMERIC')
						THEN '(' + CONVERT(NVARCHAR(10),c.precision) + ',' + CONVERT(NVARCHAR(10),c.scale) + ')'
					ELSE ''
					END
		FROM sys.columns c
		INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
		WHERE c.object_id = OBJECT_ID(@TableName)
			AND	t.name NOT IN ('IMAGE','TEXT')

		SET @colNamesString = (
				SELECT '!,' + c.Name
				FROM @colNamesTABLE c
				ORDER BY c.Ordinal
				FOR XML PATH(''),TYPE
				).value('.','NVARCHAR(MAX)')

		SET @colNamesStringDT = (
				SELECT '!,' + c.Name + ' ' + c.DataType
				FROM @colNamesTable c
				ORDER BY c.Ordinal
				FOR XML PATH(''),TYPE
				).value('.','NVARCHAR(MAX)')

		-------------------------
		--	Generate SQL String - Audit Table
		-------------------------
		SELECT @tblCreate1 = 'CREATE TABLE ' + @SchemaName + '.' + @AuditName + ' ('
				+ @crlf + @t + '[AuditID] INT IDENTITY(0,1)'
				+ @crlf + @t + ',[AuditAction] VARCHAR(15)'
				+ @crlf + @t + ',[AuditColumns] NVARCHAR(MAX)'
				+ @crlf + @t + ',[AuditDate] DATETIME2 DEFAULT GETDATE()'
				+ @crlf + @t + ',[AuditUser] SYSNAME DEFAULT SYSTEM_USER'
				+ @crlf + @t + ',[AuditSQLExec] NVARCHAR(MAX)'
				+ REPLACE(@colNamesStringDT,'!',@crlf + @t)
				+ @crlf + @t + ')'
				+ @crlf + @crlf

		SELECT @tblCreate2 = 'INSERT ' + @SchemaName + '.' + @AuditName + ' ('
				+ @crlf + @t + '[AuditAction]'
				+ @crlf + @t + ',[AuditColumns]'
				+ @crlf + @t + ',[AuditDate]'
				+ @crlf + @t + ',[AuditUser]'
				+ @crlf + @t + ',[AuditSQLExec]'
				+ @crlf + @t + ')'
				+ @crlf + 'SELECT ''CREATOR_NOTE'''
				+ @crlf + @t + ',''This audit table was created by ' + @UserName + ' in pair with the ' + @TriggerName + ' trigger. '
					+ 'The trigger will remove itself ' + ISNULL(CONVERT(NVARCHAR(20),@TriggerLifespan),'XXXXX') + ' days after creation '
					+ 'or if the audit table exceeds ' + ISNULL(CONVERT(NVARCHAR(20),@AuditSizeLimit),'XXXXX') + ' MB.'''
				+ @crlf + @t + ',GETDATE()'
				+ @crlf + @t + ',''' + @UserName + ''''
				+ @crlf + @t + ',''--DROP TRIGGER ' + @TriggerName + ' DROP TABLE ' + @AuditName + ''''

		-------------------------
		--	Generate SQL String - Trigger
		-------------------------
		SELECT @trgCreate1 = ISNULL(@pvtQuery,'')
				+ @crlf + '--initial trigger creation by util_CreateAuditTrigger'
				+ @crlf + 'CREATE TRIGGER ' + @SchemaName + '.' + @TriggerName + ' ON ' + @SchemaName + '.' + @TableName
				+ @crlf + 'AFTER INSERT, DELETE, UPDATE'
				+ @crlf + 'AS'
				+ @crlf + 'BEGIN'
				+ @crlf + @t + 'SET NOCOUNT ON;'
				+ @crlf
				+ CASE WHEN @TriggerLifespan IS NOT NULL THEN '' ELSE @crlf + @t + '/*' END
				+ @crlf + @t + 'IF EXISTS ('
				+ @crlf + @t+@t+@t + 'SELECT *'
				+ @crlf + @t+@t+@t + 'FROM sys.triggers st'
				+ @crlf + @t+@t+@t + 'WHERE st.object_id = OBJECT_ID(N''' + @SchemaName + '.' + @TriggerName + ''')'
				+ @crlf + @t+@t+@t+@t + 'AND DATEDIFF(dd,st.create_Date,GETDATE()) > ' + ISNULL(CONVERT(NVARCHAR(20),@TriggerLifespan),'XXXXX')
				+ @crlf + @t+@t+@t + ')'
				+ @crlf + @t + 'BEGIN'
				+ @crlf + @t+@t + 'SET IDENTITY_INSERT ' + @SchemaName + '.' + @AuditName + ' ON;'
				+ @crlf
				+ @crlf + @t+@t + 'INSERT ' + @SchemaName + '.' + @AuditName + ' ('
				+ @crlf + @t+@t+@t + '[AuditID]'
				+ @crlf + @t+@t+@t + ',[AuditAction]'
				+ @crlf + @t+@t+@t + ',[AuditColumns]'
				+ @crlf + @t+@t+@t + ',[AuditDate]'
				+ @crlf + @t+@t+@t + ',[AuditUser]'
				+ @crlf + @t+@t+@t + ')'
				+ @crlf + @t+@t + 'SELECT -1'
				+ @crlf + @t+@t+@t + ',''CREATOR_NOTE'''
				+ @crlf + @t+@t+@t + ',''The ' + ISNULL(CONVERT(NVARCHAR(20),@TriggerLifespan),'XXXXX') + ' day Lifespan for the ' + @TriggerName + ' trigger that populated this audit table was reached, and it has removed itself.'''
				+ @crlf + @t+@t+@t + ',GETDATE()'
				+ @crlf + @t+@t+@t + ',''' + @UserName + ''''
				+ @crlf
				+ @crlf + @t+@t + 'DROP TRIGGER ' + @SchemaName + '.' + @TriggerName
				+ @crlf + @t+@t + 'RETURN'
				+ @crlf + @t + 'END'
				+ CASE WHEN @TriggerLifespan IS NOT NULL THEN '' ELSE @crlf + @t + '*/' END
				+ @crlf
				+ CASE WHEN @AuditSizeLimit IS NOT NULL THEN '' ELSE @crlf + @t + '/*' END
				+ @crlf + @t + 'IF EXISTS ('
				+ @crlf + @t+@t+@t + 'SELECT SUM(a.total_pages)'
				+ @crlf + @t+@t+@t + 'FROM sys.partitions p'
				+ @crlf + @t+@t+@t + 'INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id'
				+ @crlf + @t+@t+@t + 'WHERE p.object_id = OBJECT_ID(N''' + @SchemaName + '.' + @AuditName + ''')'
				+ @crlf + @t+@t+@t + 'HAVING SUM(a.total_pages) > CONVERT(BIGINT,128) * ' + ISNULL(CONVERT(NVARCHAR(20),@AuditSizeLimit),'XXXXX')
				+ @crlf + @t+@t+@t + ')'
				+ @crlf + @t + 'BEGIN'
				+ @crlf + @t+@t + 'SET IDENTITY_INSERT ' + @SchemaName + '.' + @AuditName + ' ON;'
				+ @crlf
				+ @crlf + @t+@t + 'INSERT ' + @SchemaName + '.' + @AuditName + ' ('
				+ @crlf + @t+@t+@t + '[AuditID]'
				+ @crlf + @t+@t+@t + ',[AuditAction]'
				+ @crlf + @t+@t+@t + ',[AuditColumns]'
				+ @crlf + @t+@t+@t + ',[AuditDate]'
				+ @crlf + @t+@t+@t + ',[AuditUser]'
				+ @crlf + @t+@t+@t + ')'
				+ @crlf + @t+@t + 'SELECT -1'
				+ @crlf + @t+@t+@t + ',''CREATOR_NOTE'''
				+ @crlf + @t+@t+@t + ',''The size limit of ' + ISNULL(CONVERT(NVARCHAR(20),@AuditSizeLimit),'XXXXX') + ' MB for this audit table has been reached, and the ' + @TriggerName + ' trigger that populated it has removed itself.'''
				+ @crlf + @t+@t+@t + ',GETDATE()'
				+ @crlf + @t+@t+@t + ',''' + @UserName + ''''
				+ @crlf
				+ @crlf + @t+@t + 'DROP TRIGGER ' + @SchemaName + '.' + @TriggerName
				+ @crlf + @t+@t + 'RETURN'
				+ @crlf + @t + 'END'
				+ CASE WHEN @AuditSizeLimit IS NOT NULL THEN '' ELSE @crlf + @t + '*/' END
				+ @crlf + @crlf

		SELECT @trgCreate2 = @t + 'DECLARE @Date DATETIME2'
				+ @crlf + @t+@t + ',@UserName SYSNAME'
				+ @crlf + @t+@t + ',@delAction VARCHAR(15)'
				+ @crlf + @t+@t + ',@insAction VARCHAR(15)'
				+ @crlf + @t+@t + ',@updColumns NVARCHAR(MAX)'
				+ @crlf + @t+@t + ',@UserSQL NVARCHAR(MAX)'
				+ @crlf
				+ @crlf + @t + 'DECLARE @UserSQLbuffer TABLE ('
				+ @crlf + @t+@t + 'EventType NVARCHAR(30)'
				+ @crlf + @t+@t + ',Parameters INT'
				+ @crlf + @t+@t + ',EventInfo NVARCHAR(MAX)'
				+ @crlf + @t+@t + ')'
				+ @crlf
				+ @crlf + @t + 'SELECT @Date = GETDATE()'
				+ @crlf + @t+@t + ',@UserName = SYSTEM_USER'
				+ @crlf + @t+@t + ',@delAction = ''DELETED'''
				+ @crlf + @t+@t + ',@insAction = ''INSERTED'''
				+ @crlf
				+ @crlf + @t + 'IF EXISTS (SELECT * FROM deleted) AND EXISTS (SELECT * FROM inserted)'
				+ @crlf + @t+@t + 'SELECT @delAction = ''UPDATED_FROM'''
				+ @crlf + @t+@t+@t + ',@insAction = ''UPDATED_TO'''
				+ @crlf + @t+@t+@t + ',@updColumns = STUFF(('
				+ @crlf + @t+@t+@t+@t+@t + 'SELECT '','' + c.name'
				+ @crlf + @t+@t+@t+@t+@t + 'FROM sys.columns c'
				+ @crlf + @t+@t+@t+@t+@t + 'WHERE object_id = OBJECT_ID(''' + @SchemaName + '.' + @TableName + ''')'
				+ @crlf + @t+@t+@t+@t+@t+@t + 'AND sys.fn_IsBitSetInBitmask(COLUMNS_UPDATED(),c.column_id) <> 0'
				+ @crlf + @t+@t+@t+@t+@t + 'FOR XML PATH(''''),TYPE'
				+ @crlf + @t+@t+@t+@t+@t + ').value(''.'',''NVARCHAR(MAX)''),1,1,'''')'
				+ @crlf
				+ @crlf + @t + 'IF (ISNULL(@updColumns,''' + ISNULL(@inputColumnName,'') + ''') NOT LIKE ''%' + ISNULL(@inputColumnName,'') + '%'')'
				+ @crlf + @t+@t + 'RETURN'
				+ @crlf
				+ @crlf + @t + CASE @IncludeUserSQL WHEN 1 THEN '--' ELSE '' END + '/*'
				+ @crlf + @t + 'INSERT @UserSQLbuffer'
				+ @crlf + @t + 'EXEC (''DBCC INPUTBUFFER(@@SPID) with no_infomsgs'')'
				+ @crlf
				+ @crlf + @t + 'SELECT @UserSQL = EventInfo'
				+ @crlf + @t + 'FROM @UserSQLbuffer'
				+ @crlf + @t + '--*/'
				+ @crlf + @crlf

		SELECT @trgCreate3 = @t + 'INSERT ' + @SchemaName + '.' + @AuditName + ' ('
				+ @crlf + @t+@t + '[AuditAction]'
				+ @crlf + @t+@t + ',[AuditColumns]'
				+ @crlf + @t+@t + ',[AuditDate]'
				+ @crlf + @t+@t + ',[AuditUser]'
				+ @crlf + @t+@t + ',[AuditSQLExec]'
				+ REPLACE(@colNamesString,'!',@crlf + @t+@t)
				+ @crlf + @t+@t + ')'
				+ @crlf

		SELECT @trgCreate4 = @t + 'SELECT @delAction'
				+ @crlf + @t+@t + ',@updColumns'
				+ @crlf + @t+@t + ',@Date'
				+ @crlf + @t+@t + ',@UserName'
				+ @crlf + @t+@t + ',@UserSQL'
				+ REPLACE(@colNamesString,'!',@crlf + @t+@t)
				+ @crlf + @t + 'FROM deleted'
				+ @crlf + @t + 'UNION ALL'
				+ @crlf

		SELECT @trgCreate5 = @t + 'SELECT @insAction'
				+ @crlf + @t+@t + ',@updColumns'
				+ @crlf + @t+@t + ',@Date'
				+ @crlf + @t+@t + ',@UserName'
				+ @crlf + @t+@t + ',@UserSQL'
				+ REPLACE(@colNamesString,'!',@crlf + @t+@t)
				+ @crlf + @t + 'FROM inserted'
				+ @crlf + 'END'

		-------------------------
		--	Execute SQL Strings
		-------------------------
		IF (@AutoExec = 1)
		BEGIN
			EXEC (@tblCreate1 + @tblCreate2)
			EXEC (@trgCreate1 + @trgCreate2 + @trgCreate3 + @trgCreate4 + @trgCreate5)

			PRINT '>>>AUDIT TABLE AND TRIGGER SUCCESSFULLY CREATED<<<'
			PRINT 'Table Name: ' + @AuditName
			PRINT 'Trigger Name: ' + @TriggerName
			PRINT 'Trigger Lifespan: ' + ISNULL(CONVERT(NVARCHAR(20),@TriggerLifespan) + ' days', 'perpetual')
			PRINT 'Audit Size Limit: ' + ISNULL(CONVERT(NVARCHAR(20),@AuditSizeLimit) + ' MB', 'limitless')
		END
		ELSE
		BEGIN
			PRINT @tblCreate1
			PRINT @tblCreate2
			PRINT ''
			PRINT ''
			PRINT ''
			PRINT 'GO'
			PRINT ''
			PRINT ''
			PRINT ''
			PRINT @trgCreate1
			PRINT @trgCreate2
			PRINT @trgCreate3
			PRINT @trgCreate4
			PRINT @trgCreate5
		END

		COMMIT TRANSACTION
	END TRY
	BEGIN CATCH
		IF (@@TRANCOUNT > 0)
			ROLLBACK

		PRINT @pvtQuery

		SELECT @ErrorMessage = ERROR_MESSAGE()

		RAISERROR (@ErrorMessage,16,1)
	END CATCH
END
