ALTER PROCEDURE [dbo].[util_Printer] (@String VARCHAR(MAX))
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @subString VARCHAR(8000)
		,@subStart BIGINT
		,@subLength SMALLINT

	IF (LEN(@String) <= 128)
		SET @String = OBJECT_DEFINITION(OBJECT_ID(@String))

	SET @String = REPLACE(REPLACE(REPLACE(@String, CHAR(13) + CHAR(10), CHAR(10)), CHAR(13), CHAR(10)), CHAR(10), CHAR(13) + CHAR(10))
	SET @subStart = 1
	SET @subLength = 8001 - CHARINDEX(CHAR(10), REVERSE(SUBSTRING(@String, @subStart, 8000)))
	SET @subString = SUBSTRING(@String, @subStart, @subLength)

	WHILE (@subStart <= LEN(@String))
	BEGIN
		PRINT @subString

		SET @subStart = @subStart + @subLength
		SET @subLength = 8001 - CHARINDEX(CHAR(10), REVERSE(SUBSTRING(@String, @subStart, 8000)))
		SET @subString = SUBSTRING(@String, @subStart, @subLength)
	END
END
