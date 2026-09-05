function report = run_validation_tests()
%RUN_VALIDATION_TESTS Validate the simulator against simple analytic cases.
%   REPORT = RUN_VALIDATION_TESTS() exercises stationary/moving Source and
%   Receiver cases, 1/r spreading, image-source reflection, 3D AABB LOS,
%   seeded obstacle generation, Fresnel broad phase, and broadband
%   diffraction. Tests use SI units and throw an error if any case fails.

rootDirectory = fileparts(fileparts(mfilename('fullpath')));
addpath(rootDirectory);

testFunctions = {
    @testStaticDirectPath
    @testSphericalSpreading
    @testApproachingSource
    @testMovingReceiver
    @testBothMoving
    @testReflectionGeometry
    @testObstacleFaceReflection
    @testReflectionOcclusion
    @testSegmentObstruction
    @testObstacleSeedReproducibility
    @testFresnelSelection
    @testKnifeEdgeReferenceValues
    @testFiniteBoxDiffractionGeometry
    @testBroadbandDiffraction
    @testNonblockingDiffraction
    @testDiffractionActiveMask
    @testMultipleObstaclePathFallback};

names = strings(numel(testFunctions),1);
passed = false(numel(testFunctions),1);
details = strings(numel(testFunctions),1);
for k=1:numel(testFunctions)
    names(k)=string(func2str(testFunctions{k}));
    try
        testFunctions{k}();
        passed(k)=true;
        details(k)="OK";
    catch exception
        details(k)=string(getReport(exception,'basic','hyperlinks','off'));
    end
end

report=table(names,passed,details,'VariableNames',{'Test','Passed','Details'});
disp(report(:,{'Test','Passed'}));
if any(~passed)
    failed=strjoin(cellstr(names(~passed)),', ');
    error('acoustics:ValidationFailed','Validation failed: %s',failed);
end
fprintf('All %d acoustic validation tests passed.\n',height(report));
end

function testStaticDirectPath()
c=343;
source=entity([0 0 1.5],[0 0 0],[0 0 0]);
receiver=entity([10 0 1.5],[0 0 0],[0 0 0]);
t=(0:0.01:0.5).';
path=acoustics.solveDirectPath(source,receiver,t,c,solver());
assertNear(path.distanceM,10,1e-10,'Static distance');
assertNear(path.delaySec,10/c,1e-10,'Static delay');
assertNear(path.dopplerFactor,1,1e-12,'Static Doppler factor');
assert(all(path.valid),'Static path should be valid.');
end

function testSphericalSpreading()
t=(0:0.001:1).'; sourcePa=ones(size(t)); visibility=true(size(t));
path10=struct('emissionTimeSec',t,'distanceM',10*ones(size(t)),'valid',true(size(t)));
path20=struct('emissionTimeSec',t,'distanceM',20*ones(size(t)),'valid',true(size(t)));
y10=acoustics.synthesizeDirect(sourcePa,t,path10,1,0.5,visibility);
y20=acoustics.synthesizeDirect(sourcePa,t,path20,1,0.5,visibility);
levelDifferenceDb=20*log10(sqrt(mean(y10.^2))/sqrt(mean(y20.^2)));
assertNear(levelDifferenceDb,20*log10(2),1e-10,'Doubling-distance level difference');
end

function testApproachingSource()
c=343; velocity=20;
source=entity([-100 0 0],[velocity 0 0],[0 0 0]);
receiver=entity([0 0 0],[0 0 0],[0 0 0]);
path=acoustics.solveDirectPath(source,receiver,0.5,c,solver());
expected=1/(1-velocity/c);
assertNear(path.dopplerFactor,expected,1e-9,'Approaching Source Doppler');
assert(path.dopplerFactor>1,'Approaching Source must raise frequency.');
end

function testMovingReceiver()
c=343; velocity=15;
source=entity([0 0 0],[0 0 0],[0 0 0]);
receiver=entity([100 0 0],[-velocity 0 0],[0 0 0]);
path=acoustics.solveDirectPath(source,receiver,0.5,c,solver());
expected=1+velocity/c;
assertNear(path.dopplerFactor,expected,1e-9,'Approaching Receiver Doppler');
end

function testBothMoving()
c=343; velocity=18;
source=entity([0 0 0],[velocity 0 0],[0 0 0]);
receiver=entity([100 0 0],[velocity 0 0],[0 0 0]);
path=acoustics.solveDirectPath(source,receiver,(0:0.02:1).',c,solver());
assertNear(path.dopplerFactor,1,1e-10,'Equal-velocity Doppler');
end

function testReflectionGeometry()
source=entity([0 0 1],[0 0 0],[0 0 0]);
receiver=entity([4 0 1],[0 0 0],[0 0 0]);
plane=struct('id',"ground",'pointM',[0 0 0],'normal',[0 0 1], ...
    'pressureReflectionCoefficient',0.6,'boundsMinM',[-Inf -Inf -Inf], ...
    'boundsMaxM',[Inf Inf Inf]);
path=acoustics.solveReflectionPath(source,receiver,(0.1:0.01:0.2).', ...
    plane,343,solver());
assert(all(path.valid),'Ground reflection must be valid.');
assertNear(path.distanceM,sqrt(20),1e-9,'Image-source distance');
assertNear(path.sourceToReflectionM+path.reflectionToReceiverM, ...
    path.distanceM,1e-9,'Broken/image path equality');
assertNear(path.reflectionPointM(:,1),2,1e-9,'Reflection point x');
assertNear(path.reflectionPointM(:,3),0,1e-9,'Reflection point z');
end

function testObstacleFaceReflection()
fs=8000;
t=(0:1/fs:0.2-1/fs).';
sourcePa=sin(2*pi*600*t);
source=entity([-2 -1 1],[0 0 0],[0 0 0]);
receiver=entity([-2 1 1],[0 0 0],[0 0 0]);
obstacle=boxObstacle(1,[0 0 1],1,2,2);
[paths,signal]=acoustics.synthesizeObstacleReflections(sourcePa,t,source, ...
    receiver,t,obstacle,343,solver(),1,0.5,0.01);
faceNames=string({paths.faceName});
xMinimumPath=find(faceNames=="x_min",1);
assert(~isempty(xMinimumPath) && any(paths(xMinimumPath).valid), ...
    'Visible finite x-min obstacle face should create a specular path.');
assert(sqrt(mean(signal.^2))>0,'Obstacle face reflection must be nonzero.');
end

function testReflectionOcclusion()
fs=8000;
t=(0:1/fs:0.2-1/fs).';
sourcePa=sin(2*pi*600*t);
source=entity([0 0 1],[0 0 0],[0 0 0]);
receiver=entity([4 0 1],[0 0 0],[0 0 0]);
plane=struct('id',"ground",'pointM',[0 0 0],'normal',[0 0 1], ...
    'pressureReflectionCoefficient',0.6,'boundsMinM',[-Inf -Inf -Inf], ...
    'boundsMaxM',[Inf Inf Inf],'oneSided',true);
blocker=boxObstacle(1,[1 0 1],0.5,1,2);
[paths,signal]=acoustics.synthesizeReflections(sourcePa,t,source,receiver,t, ...
    plane,343,solver(),1,0.5,blocker,0.01);
assert(~any(paths.valid), ...
    'Reflection whose leg penetrates an obstacle must be invalid.');
assert(all(signal==0),'Occluded reflection component must be zero.');
end

function testSegmentObstruction()
minimum=[-0.5 -0.5 0]; maximum=[0.5 0.5 2];
[hit,t0,t1]=acoustics.segmentAABB([-2 0 1],[2 0 1],minimum,maximum);
assert(hit && t0<t1,'Segment should cross AABB.');
miss=acoustics.segmentAABB([-2 2 1],[2 2 1],minimum,maximum);
assert(~miss,'Offset segment must not cross AABB.');
obstacle=boxObstacle(1,[0 0 1],1,1,2);
result=acoustics.computeObstruction([-2 0 1;-2 2 1], ...
    [2 0 1;2 2 1],obstacle,[0;1]);
assert(isequal(result.blocked,[true;false]),'Time-varying LOS mask is wrong.');
end

function testObstacleSeedReproducibility()
config=default_config(); obstacleConfig=config.obstacle;
obstacleConfig.count=6; obstacleConfig.seed=123;
obstacleConfig.boundsMinM=[10 -10 0]; obstacleConfig.boundsMaxM=[40 10 0];
positions=repmat([0 0 1],11,1);
a=acoustics.generateObstacles(obstacleConfig,positions,positions+[0 1 0]);
b=acoustics.generateObstacles(obstacleConfig,positions,positions+[0 1 0]);
assert(isequaln(a,b),'Same seed and conditions must reproduce identical boxes.');
end

function testFresnelSelection()
source=repmat([0 0 1.5],3,1); receiver=repmat([50 0 1.2],3,1);
obstacles=[boxObstacle(1,[25 0 1],1,1,2); ...
           boxObstacle(2,[25 20 1],1,1,2); ...
           boxObstacle(3,[70 0 1],1,1,2)];
[selected,diagnostics]=acoustics.fresnelSelect(obstacles,source,receiver,500,343);
assert(diagnostics.candidateMask(1),'Near-axis obstacle must be selected.');
assert(~diagnostics.candidateMask(2),'Far lateral obstacle must be excluded.');
assert(~diagnostics.candidateMask(3),'Obstacle beyond endpoints must be excluded.');
assert(isscalar(selected),'Exactly one Fresnel candidate is expected.');
end

function testKnifeEdgeReferenceValues()
loss=acoustics.knifeEdgeLoss([0;-1]);
assertNear(loss(1),6.03285220856361,1e-10,'Knife-edge v=0 loss');
assertNear(loss(2),0,0,'Knife-edge clear-path loss');
end

function testFiniteBoxDiffractionGeometry()
% A finite-thickness box needs distinct entry/exit edge points; a single
% point would make one leg pass through the box interior.
source=[0 0 1.5]; receiver=[20 0 1.5];
obstacle=boxObstacle(1,[10 0 2],1,2,4);
geometry=acoustics.chooseDiffractionEdge(source,receiver,obstacle);
assert(geometry.valid,'Finite blocked AABB must have an exposed-face bypass path.');
assert(geometry.surfaceDistanceM>0, ...
    'Finite-thickness bypass must contain a nonzero surface leg.');
assert(geometry.pathLengthM>norm(receiver-source), ...
    'Diffracted path must be longer than the direct path.');
assertNear(geometry.pathLengthM,geometry.sourceDistanceM ...
    +geometry.surfaceDistanceM+geometry.receiverDistanceM,1e-10, ...
    'Finite-box diffraction path decomposition');
end

function testBroadbandDiffraction()
config=smallDiffractionConfig();
source=entity([0 0 1.5],[0 0 0],[0 0 0]);
receiver=entity([20 0 1.5],[0 0 0],[0 0 0]);
obstacle=boxObstacle(1,[10 0 2],1,2,4);
fs=config.audio.processingSampleRateHz;
t=(0:1/fs:config.simulation.durationSec-1/fs).';
sourcePa=sin(2*pi*800*t)+0.5*sin(2*pi*1600*t);
[signal,diagnostics]=acoustics.synthesizeDiffraction(sourcePa,t,source,receiver, ...
    t,obstacle,true,config);
assert(any(diagnostics.active),'Blocking obstacle must activate diffraction.');
assert(sqrt(mean(signal.^2))>0,'Broadband diffracted signal must be nonzero.');
assert(all(diagnostics.lossReferenceDb(diagnostics.active)>0), ...
    'Blocked knife-edge loss must be positive.');
end

function testNonblockingDiffraction()
config=smallDiffractionConfig();
source=entity([0 0 1.5],[0 0 0],[0 0 0]);
receiver=entity([20 0 1.5],[0 0 0],[0 0 0]);
obstacle=boxObstacle(1,[10 8 2],1,2,4);
fs=config.audio.processingSampleRateHz;
t=(0:1/fs:config.simulation.durationSec-1/fs).';
sourcePa=sin(2*pi*800*t);
[signal,diagnostics]=acoustics.synthesizeDiffraction(sourcePa,t,source,receiver, ...
    t,obstacle,true,config);
assert(~any(diagnostics.active),'Nonblocking obstacle must not activate diffraction.');
assert(all(signal==0),'Nonblocking diffraction component must be zero.');
end

function testDiffractionActiveMask()
% Moving geometry creates clear-blocked-clear intervals. WOLA must not
% leak the blocked-interval component back into LOS-clear samples.
config=smallDiffractionConfig();
config.simulation.durationSec=0.5;
config.simulation.geometryTimeStepSec=0.05;
config.audio.processingSampleRateHz=4000;
config.diffraction.windowLengthSamples=128;
config.diffraction.overlapSamples=96;
config.diffraction.fftLength=128;
source=entity([0 -3 1.5],[0 12 0],[0 0 0]);
receiver=entity([20 0 1.5],[0 0 0],[0 0 0]);
obstacle=boxObstacle(1,[10 0 2],1,2,4);
fs=config.audio.processingSampleRateHz;
t=(0:1/fs:config.simulation.durationSec-1/fs).';
sourcePa=sin(2*pi*600*t);
[signal,diagnostics]=acoustics.synthesizeDiffraction(sourcePa,t,source,receiver, ...
    t,obstacle,true,config);
assert(any(diagnostics.activeAudio) && any(~diagnostics.activeAudio), ...
    'Moving case must contain both blocked and clear intervals.');
assert(all(signal(~diagnostics.activeAudio)==0), ...
    'Diffracted WOLA output leaked into a LOS-clear interval.');
end

function testMultipleObstaclePathFallback()
% Two serial blockers use the documented vertical taut-path fallback when
% no valid single-box bypass can clear the other obstacle.
config=smallDiffractionConfig();
config.simulation.durationSec=0.1;
config.simulation.geometryTimeStepSec=0.05;
config.diffraction.unsupportedMultiplePathAction="ignore";
source=entity([0 0 1.5],[0 0 0],[0 0 0]);
receiver=entity([20 0 1.5],[0 0 0],[0 0 0]);
obstacles=[boxObstacle(1,[8 0 2],1,2,4); ...
           boxObstacle(2,[12 0 2],1,2,4)];
fs=config.audio.processingSampleRateHz;
t=(0:1/fs:config.simulation.durationSec-1/fs).';
sourcePa=sin(2*pi*800*t);
[signal,diagnostics]=acoustics.synthesizeDiffraction(sourcePa,t,source,receiver, ...
    t,obstacles,[true;true],config);
assert(any(diagnostics.active), ...
    'Serial blockers must produce a path-equivalent fallback diffraction ray.');
assert(any(diagnostics.multiplePathApproximationUsed), ...
    'Serial-blocker approximation must be recorded explicitly.');
assert(~any(diagnostics.unsupportedMultiplePath), ...
    'The simple serial-box case should be handled by the fallback path.');
assert(sqrt(mean(signal.^2))>0, ...
    'Handled serial blockers must not cause physically impossible silence.');
end

function config=smallDiffractionConfig()
config=default_config();
config.simulation.durationSec=0.25;
config.simulation.geometryTimeStepSec=0.01;
config.audio.processingSampleRateHz=8000;
config.diffraction.windowLengthSamples=256;
config.diffraction.overlapSamples=192;
config.diffraction.fftLength=256;
end

function value=entity(position,velocity,acceleration)
value=struct('initialPositionM',position,'initialVelocityMps',velocity, ...
    'accelerationMps2',acceleration);
end

function value=solver()
value=struct('maxIterations',30,'timeToleranceSec',1e-11);
end

function obstacle=boxObstacle(id,center,width,depth,height)
center=[center(1),center(2),height/2];
half=[width/2,depth/2,height/2];
obstacle=struct('id',"OBS_"+compose('%03d',id),'centerM',center, ...
    'widthM',width,'depthM',depth,'heightM',height, ...
    'minCornerM',center-half,'maxCornerM',center+half, ...
    'material',"test",'pressureReflectionCoefficient',0.7);
end

function assertNear(actual,expected,tolerance,label)
difference=max(abs(actual-expected),[],'all');
assert(difference<=tolerance, ...
    '%s differs by %.6g (tolerance %.6g).',label,difference,tolerance);
end
