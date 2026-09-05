function simulationId = createSimulationId(config)
%CREATESIMULATIONID Create a deterministic identifier from experiment settings.
%   ID = CREATESIMULATIONID(CONFIG) returns CONFIG.simulation.id when it is
%   nonempty. Otherwise it computes an FNV-1a-style 32-bit hash of the JSON
%   configuration. Identical settings produce the same ID.

if isfield(config.simulation, 'id') && strlength(string(config.simulation.id)) > 0
    simulationId = string(config.simulation.id);
    assertValidId(simulationId);
    return;
end

hashConfig = config;
hashConfig.simulation.id = "";
hashConfig = encodeNonfiniteExplicitly(hashConfig);
encoded = unicode2native(jsonencode(hashConfig), 'UTF-8');

hashValue = uint32(2166136261);
for k = 1:numel(encoded)
    mixed = bitxor(hashValue, uint32(encoded(k)));
    product = uint64(mixed) * uint64(16777619);
    hashValue = uint32(bitand(product, uint64(4294967295)));
end

simulationId = "SIM_" + upper(string(dec2hex(hashValue, 8)));
assertValidId(simulationId);
end

function value=encodeNonfiniteExplicitly(value)
%ENCODENONFINITEEXPLICITLY Preserve Inf signs instead of JSON null values.
if isstruct(value)
    fields=fieldnames(value);
    for elementIndex=1:numel(value)
        for fieldIndex=1:numel(fields)
            value(elementIndex).(fields{fieldIndex})=encodeNonfiniteExplicitly( ...
                value(elementIndex).(fields{fieldIndex}));
        end
    end
elseif iscell(value)
    for elementIndex=1:numel(value)
        value{elementIndex}=encodeNonfiniteExplicitly(value{elementIndex});
    end
elseif isnumeric(value) && any(~isfinite(value),'all')
    value="nonfinite_numeric:"+string(mat2str(value,17));
end
end

function assertValidId(simulationId)
if isempty(regexp(char(simulationId), '^[A-Za-z0-9_-]+$', 'once'))
    error('acoustics:InvalidSimulationId', ...
        'Simulation ID may contain only letters, digits, underscore, and hyphen.');
end
end
