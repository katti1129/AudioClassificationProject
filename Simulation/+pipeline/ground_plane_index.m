function index = ground_plane_index(config)
%GROUND_PLANE_INDEX Locate existing ground plane, or return [].
%   INDEX identifies reflection.planes whose ID is 'ground'; no plane is added.
index = [];
if ~isempty(config.reflection.planes)
    index = find(strcmpi(string({config.reflection.planes.id}),'ground'),1);
end
end

