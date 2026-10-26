function key = diffractionPathKey(g, obstacles)
%DIFFRACTIONPATHKEY Identify ray topology, not its changing coordinates.
% Input: selected geometry and static AABBs [m]. Output: stable string key.
% Single-box identity includes face/entry/exit edges. Serial paths include
% ordered contact constraints on the boxes. Coordinates along an edge are
% deliberately excluded so ordinary motion retains the same identity.
if ~g.valid,key="";return;end
if ~g.multiplePathApproximation
    key=compose('single:%d:face%d:entry%d:exit%d',g.obstacleIndex, ...
        g.faceIndex,g.entryEdgeIndex,g.exitEdgeIndex);
    return;
end
contacts=strings(size(g.diffractionPointsM,1),1);
tol=1e-6; % Numerical coordinate matching [m], not an acoustic coefficient.
for j=1:numel(contacts)
    p=g.diffractionPointsM(j,:);parts=strings(0,1);
    for k=g.obstacleIndices(:).'
        mn=obstacles(k).minCornerM;mx=obstacles(k).maxCornerM;
        if all(p>=mn-tol & p<=mx+tol)
            sides=[abs(p-mn)<tol,abs(p-mx)<tol];
            parts(end+1)=string(k)+":"+join(string(find(sides)),"."); %#ok<AGROW>
        end
    end
    contacts(j)=join(parts,"+");
end
key="serial:"+join(contacts,">");
end
