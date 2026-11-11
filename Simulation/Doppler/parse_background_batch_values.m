function values = parse_background_batch_values(text)
%PARSE_BACKGROUND_BATCH_VALUES Parse a literal numeric list WITHOUT eval.
% Input: scalar text, e.g. '5, 10, 20'. Output: finite nonnegative row vector.
% Accept spaces, commas, semicolons and Japanese commas; no colon expressions.
if ~(ischar(text) && isrow(text) || isstring(text) && isscalar(text))
    error('backgroundBatch:List','Enter a nonempty numeric list.');
end
parts=regexp(strtrim(char(text)),'[,;\s、，]+','split');
values=str2double(parts);
if isempty(values) || any(~isfinite(values)) || any(values<0) || ~isreal(values)
    error('backgroundBatch:List','Use finite nonnegative numbers separated by commas or spaces (no expressions).');
end
if numel(unique(values))~=numel(values)
    error('backgroundBatch:Duplicate','Duplicate sweep values are not allowed.');
end
end
