function [report,configs] = background_batch_plan(config,batch)
%BACKGROUND_BATCH_PLAN Construct distance x speed conditions analytically.
% Inputs: existing background config; batch from background_batch_config.
% Outputs: auditable table and cell array of per-condition existing configs.
% d is HORIZONTAL CPA [m]. Let v=Vs-Vr (horizontal), n perpendicular to v.
% Set S0_xy=R0_xy+d*n-v*tCPA. Then (S(tCPA)-R(tCPA)).v=0,
% horizontal CPA=d; 3-D CPA=sqrt(d^2+(zs-zr)^2) for constant heights.
% Choose sign(n) towards the original Source side of the relative-velocity
% line. Exact on-line ties use the left normal [-vy,vx]/|v| deterministically.
% CPA is simultaneous geometry, NOT the minimum retarded acoustic path.
validateattributes(batch.distancesM,{'numeric'},{'vector','nonempty','real','finite','nonnegative'});
validateattributes(batch.sourceSpeedsKmh,{'numeric'},{'vector','nonempty','real','finite','nonnegative'});
validateattributes(batch.cpaTimeSec,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(batch.sourceHeadingDeg,{'numeric'},{'scalar','real','finite','>=',-180,'<=',180});
if numel(unique(batch.distancesM))~=numel(batch.distancesM) || numel(unique(batch.sourceSpeedsKmh))~=numel(batch.sourceSpeedsKmh)
    error('backgroundBatch:Duplicate','Duplicate sweep values are not allowed.');
end
count=numel(batch.distancesM)*numel(batch.sourceSpeedsKmh);
if count>1000, error('backgroundBatch:TooMany','Limit each batch to 1000 conditions.'); end
validateattributes(config.fs,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(config.c,{'numeric'},{'scalar','real','positive','finite'});
validateattributes(config.wavFullScalePa,{'numeric'},{'scalar','real','positive','finite'});
for entity={'source','receiver'}
    e=config.(entity{1});
    validateattributes(e.positionM,{'numeric'},{'vector','numel',3,'real','finite'});
    validateattributes(e.velocityMps,{'numeric'},{'vector','numel',3,'real','finite'});
    if e.positionM(3)<=0 || e.velocityMps(3)~=0
        error('backgroundBatch:Geometry','Positive heights and horizontal motion are required.');
    end
end
if norm(config.receiver.velocityMps)>=config.c
    error('backgroundBatch:ReceiverSpeed','Receiver must remain subsonic.');
end
info=audioinfo(config.inputFile);
inputDuration=ceil(info.TotalSamples*config.fs/info.SampleRate)/config.fs;
if batch.cpaTimeSec>=inputDuration
    error('backgroundBatch:CpaRange','Common CPA time must be inside the emitted WAV interval [0,duration).');
end
configs=cell(count,1); records=cell(count,1); k=0;
receiver=reshape(config.receiver.positionM,1,3);
vr=reshape(config.receiver.velocityMps,1,3);
originalOffset=reshape(config.source.positionM,1,3)-receiver;
for distance=reshape(batch.distancesM,1,[])
    for speed=reshape(batch.sourceSpeedsKmh,1,[])
        k=k+1; c=config;
        vs=speed/3.6*[cosd(batch.sourceHeadingDeg),sind(batch.sourceHeadingDeg),0];
        v=vs-vr; relativeSpeed=norm(v(1:2));
        row=struct('BatchID',"",'ConditionID',string(sprintf('C%04d_D%gm_V%gkmh',k,distance,speed)), ...
            'HorizontalCpaRequestedM',distance,'SourceSpeedKmh',speed,'SourceHeadingDeg',batch.sourceHeadingDeg, ...
            'CpaRequestedSec',batch.cpaTimeSec,'GeometricCpaTimeSec',NaN,'HorizontalCpaActualM',NaN,'Cpa3DM',NaN, ...
            'SourceX0M',NaN,'SourceY0M',NaN,'SourceZ0M',config.source.positionM(3), ...
            'SourceVxMps',vs(1),'SourceVyMps',vs(2), ...
            'ReceiverX0M',receiver(1),'ReceiverY0M',receiver(2),'ReceiverZ0M',receiver(3), ...
            'ReceiverVxMps',vr(1),'ReceiverVyMps',vr(2),'ReceiverSpeedMps',norm(vr), ...
            'RelativeSpeedMps',relativeSpeed,'NormalX',NaN,'NormalY',NaN, ...
            'FsHz',config.fs,'WavFullScalePa',config.wavFullScalePa,'InputWav',string(config.inputFile), ...
            'BackgroundEnabled',logical(config.background.enabled),'BackgroundFile',string(config.background.file), ...
            'BackgroundMode',string(config.background.mode),'BackgroundSplRequestedDb',config.background.splDb, ...
            'SnrRequestedDb',config.background.snrDb,'BackgroundTimeReference',string(config.background.timeReference), ...
            'BackgroundOffsetSec',config.background.startOffsetSec,'BackgroundSourceStartSec',config.background.sourceStartSec, ...
            'BackgroundDurationSec',config.background.durationSec,'BackgroundFadeSec',config.background.fadeSec, ...
            'ActualBackgroundStartSec',NaN,'ActualBackgroundEndSec',NaN,'ActualBackgroundSplDb',NaN,'ActualSnrDb',NaN, ...
            'OutputDurationSec',NaN,'PeakAllComponentsFS',NaN,'Status',"READY",'ErrorID',"",'Message',"", ...
            'SimulationID',"",'OutputDirectory',"",'OutputWav',"");
        if norm(vs)>=config.c
            row.Status="INVALID"; row.ErrorID="backgroundBatch:SourceSpeed"; row.Message="Source speed must be below sound speed.";
        elseif relativeSpeed<=1e-10
            row.Status="INVALID"; row.ErrorID="backgroundBatch:RelativeSpeed"; row.Message="Zero relative speed: no unique CPA time.";
        else
            n=[-v(2),v(1)]/relativeSpeed;
            if dot(originalOffset(1:2),n)<0, n=-n; end
            c.source.velocityMps=vs;
            c.source.positionM=[receiver(1:2)+distance*n-v(1:2)*batch.cpaTimeSec,config.source.positionM(3)];
            delta=c.source.positionM-receiver;
            actualTime=-dot(delta,v)/dot(v,v);
            actualOffset=delta+v*actualTime;
            row.SourceX0M=c.source.positionM(1); row.SourceY0M=c.source.positionM(2);
            row.GeometricCpaTimeSec=actualTime; row.HorizontalCpaActualM=norm(actualOffset(1:2)); row.Cpa3DM=norm(actualOffset);
            row.NormalX=n(1); row.NormalY=n(2); configs{k}=c;
        end
        records{k}=row;
    end
end
report=struct2table(vertcat(records{:}));
end
