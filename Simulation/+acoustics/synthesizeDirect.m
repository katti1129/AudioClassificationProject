function directPa = synthesizeDirect(sourcePa, sourceTimeSec, path, ...
    referenceDistanceM, minimumDistanceM, visibility)
%SYNTHESIZEDIRECT Generate calibrated direct-path pressure at the Receiver.
%   DIRECTPA = SYNTHESIZEDIRECT(SOURCEPA, SOURCETIMESEC, PATH,
%   REFERENCEDISTANCEM, MINIMUMDISTANCEM, VISIBILITY) samples the real WAV
%   pressure [Pa] at PATH.emissionTimeSec, applies free-field point-source
%   spreading referenceDistance/pathLength, and applies a LOS visibility
%   mask. The minimum distance [m] prevents the 1/r point-source model from
%   diverging outside its useful near-field range.

arguments
    sourcePa (:,1) double
    sourceTimeSec (:,1) double
    path (1,1) struct
    referenceDistanceM (1,1) double {mustBePositive}
    minimumDistanceM (1,1) double {mustBePositive}
    visibility (:,1) logical
end

if numel(visibility) ~= numel(path.emissionTimeSec)
    error('acoustics:VisibilitySize', 'Visibility must match the path time axis.');
end
emittedPa = interp1(sourceTimeSec, sourcePa, path.emissionTimeSec, 'linear', 0);
spreading = referenceDistanceM ./ max(path.distanceM, minimumDistanceM);
if isfield(path,'valid')
    pathValid = double(path.valid(:));
else
    pathValid = ones(size(visibility));
end
directPa = emittedPa .* spreading .* double(visibility) .* pathValid;
end
