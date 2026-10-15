function checks = test_ambulance_transitions(o)
%TEST_AMBULANCE_TRANSITIONS Render full real WAV in controlled moving scenes.
% Input: validation options. Output: check rows, artifacts in runDir only.
% No looping; default observation is 10 s, with a post-run delay-tail check.
% A fixture that fails to produce its intended event FAILs coverage instead
% of claiming a continuity pass. Each case is isolated so errors are retained.
info=audioinfo(o.inputWav);
names=["static","source_pass","receiver_pass","both_moving", ...
    "ground_reflection","nonblocking","los_transition", ...
    "finite_face_transition","ground_occlusion","diffraction_switch"];
if isfield(o,'caseNames')&&~isempty(o.caseNames),names=names(ismember(names,string(o.caseNames)));end
checks=table();
for name=names
    fprintf('Ambulance case: %s\n',name);
    try
        c=default_config();c.simulation.id="AMB_"+upper(name);
        c.simulation.durationSec=max(o.observationDurationSec,info.Duration+.5);
        c.simulation.geometryTimeStepSec=o.geometryStepSec;
        c.audio.inputFile=o.inputWav;c.audio.sampleRateHz=o.fs;c.audio.loopInput=false;
        c.source.initialPositionM=[-10 0 1.5];c.source.initialVelocityMps=[0 0 0];
        c.source.accelerationMps2=[0 0 0];
        c.receiver.initialPositionM=[10 0 1.5];c.receiver.initialVelocityMps=[0 0 0];
        c.receiver.accelerationMps2=[0 0 0];
        c.obstacle.enabled=false;c.obstacle.manualObstacles=struct([]);
        c.reflection.enabled=false;c.reflection.obstacleFacesEnabled=false;
        c.diffraction.enabled=false;c.diffraction.unsupportedMultiplePathAction="warning";
        c.output.rootDir=fullfile(o.runDir,'ambulance');c.output.overwrite=false;
        c.output.writeMat=true;c.output.writeFigures=false;c.output.writeExcel=false;
        c.output.writeComponentWav=true;c.output.wavClippingPolicy="error";
        switch name
            case {"source_pass","both_moving"}
                c.source.initialPositionM=[-40 0 1.5];c.source.initialVelocityMps=[10 0 0];
                c.receiver.initialPositionM=[0 10 1.5];
                if name=="both_moving",c.receiver.initialVelocityMps=[1 0 0];end
            case "receiver_pass"
                c.source.initialPositionM=[0 0 1.5];
                c.receiver.initialPositionM=[-40 10 1.5];c.receiver.initialVelocityMps=[10 0 0];
            case "ground_reflection"
                c.reflection.enabled=true;
            case "nonblocking"
                c.obstacle.enabled=true;c.diffraction.enabled=true;
                c.obstacle.manualObstacles=researchtest.box(1,[0 10],1,2,4);
            case {"los_transition","ground_occlusion","diffraction_switch"}
                c.source.initialPositionM=[0 -8 1.5];c.source.initialVelocityMps=[0 2 0];
                c.receiver.initialPositionM=[20 0 1.5];c.obstacle.enabled=true;
                c.obstacle.manualObstacles=researchtest.box(1,[10 0],1,2,4);
                c.diffraction.enabled=true;
                if name=="ground_occlusion"
                    c.source.initialPositionM(3)=2;c.receiver.initialPositionM(3)=2;
                    c.obstacle.manualObstacles=researchtest.box(1,[10 0],1,2,1.1);
                    c.reflection.enabled=true;c.diffraction.enabled=false;
                elseif name=="diffraction_switch"
                    c.obstacle.manualObstacles=[researchtest.box(1,[8 -.6],1,2,4); ...
                        researchtest.box(2,[12 .6],1,2,4)];
                end
            case "finite_face_transition"
                % Parallel offset avoids Source/Receiver coincidence at t=4 s.
                % Thus near-field clamping cannot confound the wall-edge test.
                c.source.initialPositionM=[-12 -8 1.5];c.source.initialVelocityMps=[0 2 0];
                c.receiver.initialPositionM=[-10 0 1.5];
                c.obstacle.enabled=true;c.obstacle.manualObstacles=researchtest.box(1,[0 0],1,2,4);
                c.reflection.enabled=true;c.reflection.planes=struct([]);
                c.reflection.obstacleFacesEnabled=true;
        end
        r=acoustics.runSimulation(c);
        [rows,detail]=measure_signal_and_path_quality(r,o,name);
        rows=[rows;researchtest.check(name,'outside_near_field_clamp', ...
            double(min(r.paths.direct.distanceM)>c.physics.minimumDistanceM),1,0,'boolean', ...
            'Fixtures must not mix boundary transitions with a near-zero Source/Receiver distance')];
        % Observed active-path maximum, not a general future-geometry bound.
        required=info.Duration+detail.maxDelaySec+.25;
        rows=[rows;researchtest.check(name,'tail_duration_sufficient',double(c.simulation.durationSec>=required),1,0,'boolean', ...
            sprintf('Required %.6f s = full WAV + largest observed path delay + 0.25 s guard; actual %.6f s',required,c.simulation.durationSec))];
        rows=[rows;researchtest.check(name,'input_not_looped',double(r.audio.looped),0,0,'boolean','Full WAV followed by zeros')];
        [wav,fs]=audioread(r.output.audioFiles.final);
        rows=[rows;researchtest.check(name,'wav_sample_rate',fs,o.fs,0,'Hz','Rendered file'); ...
            researchtest.check(name,'wav_clipped_samples',nnz(abs(wav)>=1),0,0,'samples','Fixed shared pressure scale'); ...
            researchtest.check(name,'wav_pressure_readback',max(abs(wav*r.output.paPerFullScale-r.signals.finalPa)),0,2e-6*r.output.paPerFullScale,'Pa','No peak normalization')];
        mid=detail.events.TimeSec>.5 & detail.events.TimeSec<info.Duration-.5;
        switch name
            case "los_transition"
                count=nnz(mid & detail.events.Path=="direct");
                rows=[rows;coverage(name,'LOS_boundaries_exercised',count,2)];
            case "finite_face_transition"
                count=nnz(mid & startsWith(detail.events.Path,'OBS_'));
                rows=[rows;coverage(name,'finite_face_boundaries_exercised',count,2)];
            case "ground_occlusion"
                count=nnz(mid & detail.events.Path=="ground");
                rows=[rows;coverage(name,'ground_boundaries_exercised',count,2)];
            case "diffraction_switch"
                w=detail.warp;
                if isempty(w),count=0;else,count=nnz(w.ObstacleSetChanged & w.StartSec>.5 & w.EndSec<info.Duration-.5);end
                rows=[rows;coverage(name,'diffraction_switch_exercised',count,1)];
            case {"source_pass","receiver_pass","both_moving"}
                p=r.paths.direct;valid=r.timeSec>.5&r.timeSec<info.Duration-.5;
                rows=[rows;coverage(name,'approach_and_recede_exercised', ...
                    double(any(p.dopplerFactor(valid)>1.001)&&any(p.dopplerFactor(valid)<.999)),1)];
            case "nonblocking"
                rows=[rows;researchtest.check(name,'LOS_clear',nnz(r.obstruction.blocked),0,0,'frames','Offset box does not obstruct')];
            case "ground_reflection"
                rows=[rows;coverage(name,'reflection_audible_component',double(rms(r.signals.reflectedPa)>0),1)];
            case "static"
                rows=[rows;researchtest.check(name,'static_doppler',max(abs(r.paths.direct.dopplerFactor-1)),0,1e-10,'ratio','Stationary baseline')];
        end
        researchtest.save_case(r,detail,rows,o);
        checks=[checks;rows]; %#ok<AGROW>
    catch ex
        checks=[checks;researchtest.row(name,'execution','FAIL',NaN,NaN,NaN,'',getReport(ex,'extended','hyperlinks','off'))]; %#ok<AGROW>
    end
    writetable(checks,fullfile(o.runDir,'ambulance_progress.csv'));
end
end

function r = coverage(name,check,value,minimum)
%COVERAGE Require that the intended scene event really occurred.
status="FAIL";if value>=minimum,status="PASS";end
r=researchtest.row(name,check,status,value,minimum,0,'events','Measured must be >= Expected; event lies inside active input interval');
end
