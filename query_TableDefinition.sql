DECLARE @table_name SYSNAME = 'dbo.dimsoftware'



DECLARE @schema_name NVARCHAR(150)
	,@object_name NVARCHAR(300)
	,@object_id INT

SELECT @schema_name = CONCAT('[',s.[name],']')
	,@object_name = CONCAT('[',s.[name],'].[',t.[name],']')
	,@object_id = t.[object_id]
FROM sys.tables t
JOIN sys.schemas s ON t.[schema_id] = s.[schema_id]
WHERE CONCAT(s.[name],'.',t.[name]) = @table_name
	AND t.is_ms_shipped = 0

DECLARE @createtable NVARCHAR(MAX) = ''
	,@createconstraints NVARCHAR(MAX) = ''
	,@createindexes NVARCHAR(MAX) = ''
	,@r CHAR(2) = CHAR(13) + CHAR(10)
	,@t CHAR(1) = CHAR(9)

SELECT @createtable = CONCAT('IF OBJECT_ID(''',@object_name,''',''U'') IS NULL',@r
	,@t,'CREATE TABLE ',@object_name,' (',@r
	,STUFF((
		SELECT CONCAT(@t,@t,',',c.[name],' '
				,CASE c.is_computed WHEN 1 THEN CONCAT('AS ',cc.[definition]) ELSE
					CONCAT(UPPER(t.[name])
						,CASE
							WHEN t.[name] IN ('varchar','char','varbinary','binary','text') THEN CONCAT('(',CASE c.max_length WHEN -1 THEN 'MAX' ELSE CONVERT(VARCHAR(5),c.max_length) END,')')
							WHEN t.[name] IN ('nvarchar','nchar','ntext') THEN CONCAT('(',CASE c.max_length WHEN -1 THEN 'MAX' ELSE CONVERT(VARCHAR(5),c.max_length/2) END,')')
							WHEN t.[name] IN ('datetime2','time2','datetimeoffset') THEN CONCAT('(',c.scale,')')
							WHEN t.[name] = 'decimal' THEN CONCAT('(',c.[precision],',',c.scale,')')
							END
						,' GENERATED ALWAYS AS ROW '+CASE c.generated_always_type WHEN 1 THEN 'START' WHEN 2 THEN 'END' END
						,CASE c.is_hidden WHEN 1 THEN ' HIDDEN' END
						,CASE WHEN ic.is_identity = 1 THEN CONCAT(' IDENTITY',NULLIF(CONCAT('(',ISNULL(CONVERT(BIGINT,ic.seed_value),0),',',ISNULL(CONVERT(BIGINT,ic.increment_value),1),')'),'(1,1)')) END
						,CASE WHEN c.is_nullable = 1 THEN ' NULL' ELSE ' NOT NULL' END
						,' COLLATE '+NULLIF(c.collation_name,DATABASEPROPERTYEX(DB_NAME(),'collation'))
						)
				END,@r)
		FROM sys.columns c
		JOIN sys.types t ON c.user_type_id = t.user_type_id
		LEFT JOIN sys.computed_columns cc ON c.[object_id] = cc.[object_id]
			AND c.column_id = cc.column_id
		LEFT JOIN sys.identity_columns ic ON c.[object_id] = ic.[object_id]
			AND c.column_id = ic.column_id
			AND c.is_identity = 1
		WHERE c.[object_id] = @object_id
		ORDER BY c.column_id
		FOR XML PATH(N''),TYPE
		).value('.','NVARCHAR(MAX)'),3,1,'')
	,@t+@t+',PERIOD FOR SYSTEM_TIME ('+(SELECT c.[name] FROM sys.columns c WHERE c.[object_id] = @object_id AND c.generated_always_type = 1)
							+','+(SELECT c.[name] FROM sys.columns c WHERE c.[object_id] = @object_id AND c.generated_always_type = 2)+')'+@r
	,@t,@t,')'
	,' WITH (SYSTEM_VERSIONING=ON (HISTORY_TABLE='
		+(SELECT '['+OBJECT_SCHEMA_NAME(t.history_table_id)+'].['+OBJECT_NAME(t.history_table_id)+']' FROM sys.tables t WHERE t.[object_id] = @object_id)
		+'))')

SELECT @createconstraints = CONCAT(@createconstraints,(
	SELECT CONCAT(@r,'IF OBJECT_ID(''',@schema_name,'.[',ck.[name],']'',''C'') IS NULL',@r
		,'BEGIN',@r
		,@t,'ALTER TABLE ',@object_name
		,' WITH ',CASE ck.is_not_trusted WHEN 1 THEN 'NO' END,'CHECK'
		,' ADD CONSTRAINT [',ck.[name],'] CHECK ',SUBSTRING(ck.[definition],2,LEN(ck.[definition])-2)),@r
		,@t,'ALTER TABLE ',@object_name,' CHECK CONSTRAINT ',ck.[name],@r
		,'END'
	FROM sys.check_constraints ck
	WHERE ck.parent_object_id = @object_id
	ORDER BY ck.principal_id
	FOR XML PATH(N''),TYPE
	).value('.','NVARCHAR(MAX)'))

SELECT @createconstraints = CONCAT(@createconstraints,(
	SELECT CONCAT(@r,'IF OBJECT_ID(''',@schema_name,'.[',df.[name],']'',''D'') IS NULL',@r
		,@t,'ALTER TABLE ',@object_name
		,' ADD CONSTRAINT [',df.[name],'] DEFAULT ',SUBSTRING(df.[definition],2,LEN(df.[definition])-2)
		,' FOR ',COL_NAME(df.parent_object_id,df.parent_column_id))
	FROM sys.default_constraints df
	WHERE df.parent_object_id = @object_id
	ORDER BY df.principal_id
	FOR XML PATH(N''),TYPE
	).value('.','NVARCHAR(MAX)'))

SELECT @createconstraints = CONCAT(@createconstraints,(
	SELECT CONCAT(@r,'IF OBJECT_ID(''',@schema_name,'.[',k.[name],']'',''',CASE k.is_primary_key WHEN 1 THEN 'PK' ELSE 'UK' END,''') IS NULL',@r
		,@t,'ALTER TABLE ',@object_name
		,' ADD CONSTRAINT [',k.[name],'] ',CASE k.is_primary_key WHEN 1 THEN 'PRIMARY KEY' ELSE 'UNIQUE' END,' ',k.[type_desc],' ('
		,STUFF((
			SELECT CONCAT(',',c.[name],CASE ic.is_descending_key WHEN 1 THEN ' DESC' END)
			FROM sys.index_columns ic
			JOIN sys.columns c ON ic.[object_id] = c.[object_id]
				AND ic.column_id = c.column_id
			WHERE ic.[object_id] = k.[object_id]
				AND ic.index_id = k.index_id
				AND ic.is_included_column = 0
			FOR XML PATH(N''),TYPE
			).value('.','NVARCHAR(MAX)'),1,1,'')
		,')'
		,' WHERE '+SUBSTRING(k.filter_definition,2,LEN(k.filter_definition)-2)
		,' WITH (IGNORE_DUP_KEY='+CASE k.[ignore_dup_key] WHEN 1 THEN 'ON' END+')')
	FROM sys.indexes k
	WHERE k.[object_id] = @object_id
		AND 1 IN (k.is_unique_constraint,k.is_primary_key)
	ORDER BY k.index_id
	FOR XML PATH(N''),TYPE
	).value('.','NVARCHAR(MAX)'))

;WITH cFKcols AS (
	SELECT k.constraint_object_id
		,c.[name] AS cname
		,rc.[name] AS rcname
	FROM sys.foreign_key_columns k
	JOIN sys.columns rc ON k.referenced_object_id = rc.[object_id]
		AND k.referenced_column_id = rc.column_id
	JOIN sys.columns c ON k.parent_object_id = c.[object_id]
		AND k.parent_column_id = c.column_id
	WHERE k.parent_object_id = @object_id
	)
SELECT @createconstraints = CONCAT(@createconstraints,(
	SELECT CONCAT(@r,'IF OBJECT_ID(''',@schema_name,'.[',fk.[name],']'',''F'') IS NULL',@r
		,'BEGIN',@r
		,@t,'ALTER TABLE ',@object_name
		,' WITH ',CASE fk.is_not_trusted WHEN 1 THEN 'NO' END,'CHECK'
		,' ADD CONSTRAINT [',fk.[name],'] FOREIGN KEY ('
		,STUFF((
			SELECT CONCAT(',',k.cname)
			FROM cFKcols k
			WHERE k.constraint_object_id = fk.[object_id]
			FOR XML PATH(N''),TYPE
			).value('.','NVARCHAR(MAX)'),1,1,'')
		,')'
		,' REFERENCES [',SCHEMA_NAME(ro.[schema_id]),'].[',ro.[name],'] ('
		,STUFF((
			SELECT CONCAT(',',k.rcname)
			FROM cFKcols k
			WHERE k.constraint_object_id = fk.[object_id]
			FOR XML PATH(N''),TYPE
			).value('.','NVARCHAR(MAX)'),1,1,'')
		,')'
		,CASE fk.delete_referential_action
			WHEN 1 THEN ' ON DELETE CASCADE'
			WHEN 2 THEN ' ON DELETE SET NULL'
			WHEN 3 THEN ' ON DELETE SET DEFAULT'
			END
		,CASE fk.update_referential_action
			WHEN 1 THEN ' ON UPDATE CASCADE'
			WHEN 2 THEN ' ON UPDATE SET NULL'
			WHEN 3 THEN ' ON UPDATE SET DEFAULT'
			END,@r
		,@t,'ALTER TABLE ',@object_name,' CHECK CONSTRAINT [',fk.[name],']',@r
		,'END',@r)
	FROM sys.foreign_keys fk
	JOIN sys.objects ro ON fk.referenced_object_id = ro.[object_id]
	WHERE fk.parent_object_id = @object_id
	ORDER BY fk.key_index_id
	FOR XML PATH(N''),TYPE
	).value('.','NVARCHAR(MAX)'))

;WITH cIXcols AS (
	SELECT ic.index_id
		,c.[name]
		,ic.is_descending_key
		,ic.is_included_column
	FROM sys.index_columns ic
	JOIN sys.columns c ON ic.[object_id] = c.[object_id]
		AND ic.column_id = c.column_id
	WHERE ic.[object_id] = @object_id
	)
SELECT @createindexes = CONCAT(@createindexes,(
	SELECT CONCAT(@r,'IF INDEXPROPERTY(OBJECT_ID(''',@object_name,'''),''',i.[name],''',''IndexID'') IS NULL',@r
		,@t,'CREATE ',CASE i.is_unique WHEN 1 THEN 'UNIQUE ' END
		,i.[type_desc],' INDEX [',i.[name],'] ON ',@object_name
		,' ('+STUFF((
			SELECT CONCAT(',',c.[name],CASE c.is_descending_key WHEN 1 THEN ' DESC' END)
			FROM cIXcols c
			WHERE c.index_id = i.index_id
				AND c.is_included_column = 0
			FOR XML PATH(N''),TYPE
			).value('.','NVARCHAR(MAX)'),1,1,'')+')'
		,' INCLUDE ('
			+ STUFF((
				SELECT CONCAT(',',c.[name])
				FROM cIXcols c
				WHERE c.index_id = i.index_id
					AND c.is_included_column = 1
					AND i.[type] < 5
				FOR XML PATH(N''),TYPE
				).value('.','NVARCHAR(MAX)'),1,1,'')
			+ ')'
		,' WHERE '+SUBSTRING(i.filter_definition,2,LEN(i.filter_definition)-2)
		,' WITH (IGNORE_DUP_KEY='+CASE i.[ignore_dup_key] WHEN 1 THEN 'ON' END+')')
	FROM sys.indexes i
	WHERE i.[object_id] = @object_id
		AND i.is_unique_constraint = 0
		AND i.is_primary_key = 0
		AND i.[type] > 0
	ORDER BY i.index_id
	FOR XML PATH(N''),TYPE
	).value('.', 'NVARCHAR(MAX)'))

PRINT @createtable
PRINT @createconstraints
PRINT @createindexes
