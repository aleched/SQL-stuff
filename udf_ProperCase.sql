ALTER FUNCTION [dbo].[udf_ProperCase] (@String VARCHAR(MAX))
RETURNS VARCHAR(MAX)
AS 
BEGIN
    IF (LEN(@String) > 0)
	BEGIN
		--Start by setting the entire string to lowercase
		SET @String = LOWER(@String)

		DECLARE @Char CHAR(1)
			,@Break INT

		--Replace every character that follows a Space with it's uppercase version
		SET @Char = ' '
		SET @Break = 0
		WHILE (@Break <> 1)
		BEGIN
			SET @Break = CHARINDEX(@Char,@String,@Break)+1
			SET @String = ISNULL(STUFF(@String,@Break,1,UPPER(SUBSTRING(@String,@Break,1))),@String)
		END

		--Replace every character that follows a Hyphen with it's uppercase version
		SET @Char = '-'
		SET @Break = 0
		WHILE (@Break <> 1)
		BEGIN
			SET @Break = CHARINDEX(@Char,@String,@Break)+1
			SET @String = ISNULL(STUFF(@String,@Break,1,UPPER(SUBSTRING(@String,@Break,1))),@String)
		END

		--If the final string segment after the last Space is a suffix, uppercase it
		SET @String = REVERSE(@String)
		SET @Break = CHARINDEX(' ',@String)

		IF LEFT(@String,@Break) IN ('i','ii','iii','iv','v','vi')
			SET @String = STUFF(@String,1,@Break,UPPER(LEFT(@String,@Break)))

		SET @String = REVERSE(@String)

	END

    RETURN @String
END
