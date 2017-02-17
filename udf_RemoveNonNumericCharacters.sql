ALTER FUNCTION [dbo].[udf_RemoveNonNumericCharacters] (@String VARCHAR(MAX))
RETURNS VARCHAR(MAX)
AS
BEGIN
	WHILE PATINDEX('%[^0-9]%', @String) > 0
		SELECT	@String = STUFF(@String, PATINDEX('%[^0-9]%',@String) ,1,'')
	RETURN	@String
END
