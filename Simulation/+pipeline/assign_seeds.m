function rows = assign_seeds(rows, startSeed, indices)
%ASSIGN_SEEDS Assign consecutive reproducible uint32-range seeds to rows.
%   ROWS = ASSIGN_SEEDS(ROWS,START,INDICES) updates selected rows in order.
if nargin < 3, indices = (1:height(rows))'; end
indices = unique(indices(:),'stable');
validateattributes(startSeed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
if isempty(indices), return; end
validateattributes(indices,{'numeric'},{'integer','>=',1,'<=',height(rows)});
assert(startSeed+numel(indices)-1 <= 2^32-1, ...
    'pipeline:SeedOverflow','Seeds must not exceed 2^32-1.');
rows.Seed(indices) = startSeed+(0:numel(indices)-1)';
end

