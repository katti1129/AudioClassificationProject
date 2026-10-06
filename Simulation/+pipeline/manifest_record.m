function record = manifest_record(row, name, paths, runID)
%MANIFEST_RECORD Construct one stable-schema row for an attempt/current artifact.
%   Missing result diagnostics are NaN; error/status fields are populated later.
record=struct();
record.ID=string(name);
record.Filename=string(name)+".wav";
record.InputWAV=string(row.InputWAV);
[~,stem]=fileparts(char(record.InputWAV)); record.Source=string(stem);
record.CPA_m=row.CPA_m;
record.SourceVelocityKmh=row.SourceVelocityKmh;
record.ReceiverVelocityKmh=row.ReceiverVelocityKmh;
record.Profile=string(row.Profile);
record.SourceAccelerationMps2=row.SourceAccelerationMps2;
record.ReceiverAccelerationMps2=row.ReceiverAccelerationMps2;
record.GroundReflectionCoeff=row.GroundReflectionCoeff;
record.Obstacle=logical(row.Obstacle);
record.RequestedObstacleCount=row.ObstacleCount;
record.ObstacleCount=row.ObstacleCount*double(row.Obstacle);
record.Seed=row.Seed;
record.Diffraction=logical(row.Diffraction);
record.Reflection=logical(row.Reflection);
record.DurationSec=row.DurationSec;
record.Status="PENDING";
record.ErrorIdentifier="";
record.ErrorMessage="";
record.WAVPath=string(paths.wavFile);
record.ResultFolder=string(paths.resultDir);
record.CreatedAt=string(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
record.RunID=string(runID);
record.RowNumber=row.No;
record.ElapsedSec=NaN;
record.SampleRateHz=NaN;
record.PaPerFullScale=NaN;
record.AdaptiveScaleUsed=false;
record.ObservedHorizontalCPAM=NaN;
record.ObservedCPATimeSec=NaN;
record.Observed3DMinimumM=NaN;
record.MultipleDiffractionApproximationFrames=NaN;
record.UnsupportedDiffractionFrames=NaN;
record.ArchiveFolder="";
record.WarningText="";
end
