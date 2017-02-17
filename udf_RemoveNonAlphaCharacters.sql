ALTER FUNCTION [dbo].[udf_RemoveNonAlphaCharacters] (@String VARCHAR(MAX))
RETURNS VARCHAR(MAX)
AS
BEGIN
	WHILE PATINDEX('%[^a-zA-Z]%' COLLATE Latin1_General_BIN, @String) > 0
		SELECT	@String = STUFF(@String, PATINDEX('%[^a-zA-Z]%' COLLATE Latin1_General_BIN,@String) ,1,'')
	RETURN	@String
END
