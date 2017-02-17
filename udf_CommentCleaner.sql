ALTER FUNCTION [dbo].[udf_CommentCleaner] (@Text VARCHAR(MAX))
RETURNS VARCHAR(MAX)
AS
BEGIN
	-------------------------
	--	Declare Variables
	-------------------------
	DECLARE @Marker INT = 0
		,@NextLine INT = 0
		,@NextBlock INT = 0
		,@NextBlockEnd INT
		,@StuffStart INT
		,@StuffLength INT

	-------------------------
	--	Initialize Variables
	-------------------------
	--Remove invalid returns
	SET @Text = REPLACE(REPLACE(REPLACE(@Text, CHAR(13) + CHAR(10), CHAR(10)), CHAR(13), CHAR(10)), CHAR(10), CHAR(13) + CHAR(10))
	--Identify the first line comment
	SET @NextLine = CHARINDEX('--', @Text)
	--Identify the first block comment
	SET @NextBlock = CHARINDEX('/*', @Text)

	-------------------------
	--	Continue the while loop for as long as there is comment notation
	-------------------------
	WHILE (@NextLine - @NextBlock <> 0)
	BEGIN
		-------------------------
		--	Identify the next comment type, its start and length
		-------------------------
		IF ((@NextLine < @NextBlock AND @NextLine <> 0) OR @NextBlock = 0 )
		BEGIN  --Line Comment
			SET @Marker = @Marker + @NextLine
			SET @StuffStart = @Marker
			SET @StuffLength = ISNULL(NULLIF(CHARINDEX(CHAR(13) + CHAR(10), @Text, @StuffStart), 0) - @StuffStart, LEN(@Text))
		END
		ELSE
		BEGIN  --Block Comment
			SET @Marker = @Marker + @NextBlock
			SET @NextBlockEnd = ISNULL(NULLIF(CHARINDEX('*/', REPLACE(@Text, '/*', '//'), @Marker), 0) - @Marker + 2, LEN(@Text))
			SET @StuffLength = CHARINDEX('*/', REVERSE(SUBSTRING(@Text, @Marker, @NextBlockEnd))) + 1
			SET @StuffStart = @Marker + @NextBlockEnd - @StuffLength
		END

		-------------------------
		--	Determine whether the comment syntax is within a string
		-------------------------
		IF ((LEN(LEFT(@Text, @Marker)) - LEN(REPLACE(LEFT(@Text, @Marker), '''', ''))) % 2 <> 0)
		BEGIN  --Comment syntax is in a live string, skip it
			SET @Marker = CHARINDEX('''', @Text, @Marker)
			SET @NextLine = ISNULL(NULLIF(CHARINDEX('--', @Text, @Marker), 0) - @Marker, 0)
			SET @NextBlock = ISNULL(NULLIF(CHARINDEX('/*', @Text, @Marker), 0) - @Marker, 0)
		END
		ELSE
		BEGIN  --Comment syntax is active, remove it
			SET @Text = STUFF(@Text, @StuffStart, @StuffLength, ' ')
			SET @Marker = @Marker - 1
			SET @NextLine = ISNULL(NULLIF(CHARINDEX('--', @Text, @Marker), 0) - @Marker, 0)
			SET @NextBlock = ISNULL(NULLIF(CHARINDEX('/*', @Text, @Marker), 0) - @Marker, 0)
		END
	END

	-------------------------
	--	Final Output
	-------------------------
	RETURN @Text
END
