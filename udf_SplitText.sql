ALTER FUNCTION [dbo].[udf_SplitText] (
	@String VARCHAR(MAX)
	,@Delimiter CHAR(1)
	,@Num INT
	)
RETURNS VARCHAR(MAX)
AS
BEGIN
	RETURN (
		SELECT Item
		FROM dbo.udf_Split(@String,@Delimiter)
		WHERE Num = @Num
		)
END
