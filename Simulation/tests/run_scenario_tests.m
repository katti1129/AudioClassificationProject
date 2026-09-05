function report = run_scenario_tests()
%RUN_SCENARIO_TESTS Exercise requested cases through the full pipeline.
%   REPORT = RUN_SCENARIO_TESTS() runs short, output-disabled simulations
%   using the real configured WAV. It covers static/moving Source and
%   Receiver combinations, reflections, LOS blocking/nonblocking boxes,
%   Fresnel inclusion/exclusion, broadband diffraction, and seed
%   reproducibility. Each case checks a stated physical expectation.

rootDirectory=fileparts(fileparts(mfilename('fullpath')));
addpath(rootDirectory);
temporaryOutput=tempname;
cleanup=onCleanup(@() removeTemporaryOutput(temporaryOutput));

tests={@staticNoObstacle,@approachingSource,@movingReceiver,@bothMoving, ...
    @reflectionCase,@blockingDiffraction,@nonblockingObstacle, ...
    @fresnelInsideOutside,@randomSeedReproducibility};
names=strings(numel(tests),1);
passed=false(numel(tests),1);
details=strings(numel(tests),1);
for testIndex=1:numel(tests)
    names(testIndex)=string(func2str(tests{testIndex}));
    try
        tests{testIndex}();
        passed(testIndex)=true;
        details(testIndex)="OK";
    catch exception
        details(testIndex)=string(getReport(exception,'basic','hyperlinks','off'));
    end
end
report=table(names,passed,details,'VariableNames',{'Scenario','Passed','Details'});
disp(report(:,{'Scenario','Passed'}));
if any(~passed)
    error('acoustics:ScenarioValidationFailed','Scenario validation failed: %s', ...
        strjoin(cellstr(names(~passed)),', '));
end
fprintf('All %d full-pipeline scenario tests passed.\n',height(report));

    function staticNoObstacle()
        config=baseConfig("SCENARIO_STATIC");
        result=acoustics.runSimulation(config);
        assert(max(abs(result.paths.direct.dopplerFactor-1))<1e-10);
        assert(max(result.paths.direct.distanceM)-min(result.paths.direct.distanceM)<1e-10);
        assert(all(result.signals.reflectedPa==0));
        assert(all(result.signals.diffractedPa==0));
    end

    function approachingSource()
        config=baseConfig("SCENARIO_SOURCE_APPROACH");
        config.source.initialPositionM=[-20 0 1.5];
        config.source.initialVelocityMps=[10 0 0];
        config.receiver.initialPositionM=[0 0 1.5];
        result=acoustics.runSimulation(config);
        assert(all(result.paths.direct.dopplerFactor>1));
        assert(result.paths.direct.distanceM(end)<result.paths.direct.distanceM(1));
    end

    function movingReceiver()
        config=baseConfig("SCENARIO_RECEIVER_APPROACH");
        config.source.initialPositionM=[0 0 1.5];
        config.receiver.initialPositionM=[20 0 1.5];
        config.receiver.initialVelocityMps=[-10 0 0];
        result=acoustics.runSimulation(config);
        assert(all(result.paths.direct.dopplerFactor>1));
        assert(result.paths.direct.distanceM(end)<result.paths.direct.distanceM(1));
    end

    function bothMoving()
        config=baseConfig("SCENARIO_BOTH_MOVING");
        config.source.initialPositionM=[0 0 1.5];
        config.receiver.initialPositionM=[20 0 1.5];
        config.source.initialVelocityMps=[10 0 0];
        config.receiver.initialVelocityMps=[10 0 0];
        result=acoustics.runSimulation(config);
        assert(max(abs(result.paths.direct.dopplerFactor-1))<1e-9);
        assert(max(result.paths.direct.distanceM)-min(result.paths.direct.distanceM)<1e-8);
    end

    function reflectionCase()
        config=baseConfig("SCENARIO_REFLECTION");
        config.reflection.enabled=true;
        config.source.initialPositionM=[0 0 1.5];
        config.receiver.initialPositionM=[10 0 1.5];
        result=acoustics.runSimulation(config);
        assert(sqrt(mean(result.signals.reflectedPa.^2))>0);
        assert(~isempty(result.paths.reflections));
    end

    function blockingDiffraction()
        config=baseConfig("SCENARIO_BLOCKED_DIFFRACTION");
        config.obstacle.enabled=true;
        config.obstacle.manualObstacles=manualBox(1,[0 0 2],1,2,4);
        result=acoustics.runSimulation(config);
        assert(all(result.obstruction.blocked));
        assert(all(result.signals.directPa==0));
        assert(sqrt(mean(result.signals.diffractedPa.^2))>0);
    end

    function nonblockingObstacle()
        config=baseConfig("SCENARIO_NONBLOCKING");
        config.obstacle.enabled=true;
        config.obstacle.manualObstacles=manualBox(1,[0 6 2],1,2,4);
        result=acoustics.runSimulation(config);
        assert(~any(result.obstruction.blocked));
        assert(sqrt(mean(result.signals.directPa.^2))>0);
        assert(all(result.signals.diffractedPa==0));
    end

    function fresnelInsideOutside()
        config=baseConfig("SCENARIO_FRESNEL");
        config.obstacle.enabled=true;
        config.obstacle.manualObstacles=[manualBox(1,[0 0 2],1,2,4); ...
            manualBox(2,[0 12 2],1,2,4)];
        result=acoustics.runSimulation(config);
        assert(isequal(result.fresnel.candidateMask,[true;false]));
    end

    function randomSeedReproducibility()
        config=baseConfig("SCENARIO_SEED_A");
        config.obstacle.enabled=true;
        config.obstacle.count=3;
        config.obstacle.seed=777;
        config.obstacle.boundsMinM=[-5 5 0];
        config.obstacle.boundsMaxM=[5 15 0];
        a=acoustics.runSimulation(config);
        config.simulation.id="SCENARIO_SEED_B";
        b=acoustics.runSimulation(config);
        assert(isequaln(a.obstacles,b.obstacles));
    end

    function config=baseConfig(id)
        config=default_config();
        config.simulation.id=id;
        config.simulation.durationSec=0.25;
        config.simulation.geometryTimeStepSec=0.025;
        config.audio.sampleRateHz=8000;
        config.audio.internalOversampleFactor=1;
        config.audio.loopInput=false;
        config.source.initialPositionM=[-10 0 1.5];
        config.source.initialVelocityMps=[0 0 0];
        config.source.accelerationMps2=[0 0 0];
        config.receiver.initialPositionM=[10 0 1.5];
        config.receiver.initialVelocityMps=[0 0 0];
        config.receiver.accelerationMps2=[0 0 0];
        config.reflection.enabled=false;
        config.reflection.obstacleFacesEnabled=false;
        config.obstacle.enabled=false;
        config.diffraction.windowLengthSamples=128;
        config.diffraction.overlapSamples=96;
        config.diffraction.fftLength=128;
        config.output.rootDir=temporaryOutput;
        config.output.writeComponentWav=false;
        config.output.writeMat=false;
        config.output.writeExcel=false;
        config.output.writeFigures=false;
    end
end

function obstacle=manualBox(id,center,width,depth,height)
%MANUALBOX Create a ground-standing manual AABB for scenario tests.
center=[center(1),center(2),height/2];
half=[width/2,depth/2,height/2];
obstacle=struct('id',"OBS_"+compose('%03d',id),'centerM',center, ...
    'widthM',width,'depthM',depth,'heightM',height, ...
    'minCornerM',center-half,'maxCornerM',center+half, ...
    'material',"test_concrete",'pressureReflectionCoefficient',0.7);
end

function removeTemporaryOutput(directory)
%REMOVETEMPORARYOUTPUT Delete only the unique directory made by tempname.
if isfolder(directory)
    rmdir(directory,'s');
end
end
