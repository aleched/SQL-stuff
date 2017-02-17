ALTER FUNCTION [dbo].[udf_Split] (
	@String VARCHAR(MAX)
	,@Delimiter CHAR(1)
	)
RETURNS TABLE
AS
RETURN (
	SELECT ROW_NUMBER() OVER(ORDER BY number) AS Num
		,SUBSTRING(@String, number, CHARINDEX(@Delimiter, @String + @Delimiter, number) - number) AS Item
	FROM master..spt_values
	WHERE type = 'P'
		AND number <= CONVERT(INT, LEN(@String)) + 1
		AND SUBSTRING(@Delimiter + @String, number, 1) = @Delimiter
	)
