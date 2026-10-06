function rows = apply_common(rows, common, indices)
%APPLY_COMMON Copy editable common fields to rows, preserving No and Seed.
%   COMMON is a one-row condition table. INDICES defaults to every row.
if nargin < 3, indices = (1:height(rows))'; end
assert(height(common)==1,'pipeline:CommonRow','Common settings need one row.');
fields = setdiff(rows.Properties.VariableNames,{'No','Seed'},'stable');
for k=1:numel(fields)
    rows.(fields{k})(indices,:) = repmat(common.(fields{k}),numel(indices),1);
end
end

