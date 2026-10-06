function [paths, skip, archiveDir] = resolve_collision(datasetDir, name, policy)
%RESOLVE_COLLISION Resolve both WAV/result-folder conflicts as one experiment.
%   Rename selects _REP02 onward; Skip touches no experiment file; Overwrite
%   moves the previous pair into _history (recoverable) before a new attempt.
paths=pipeline.create_output_paths(datasetDir,name);
skip=false; archiveDir="";
exists=@(p)isfile(p.wavFile)||isfolder(p.resultDir);
if ~exists(paths), return; end
switch string(policy)
    case "Skip"
        skip=true;
    case "Rename"
        repetition=2;
        while exists(paths)
            paths=pipeline.create_output_paths(datasetDir, ...
                string(name)+compose('_REP%02d',repetition));
            repetition=repetition+1;
        end
    case "Overwrite"
        history=fullfile(datasetDir,'_history');
        if ~isfolder(history), mkdir(history); end
        archiveDir=string(tempname(history));
        mkdir(archiveDir);
        if isfile(paths.wavFile)
            movefile(paths.wavFile,fullfile(archiveDir,[char(paths.name),'.wav']));
        end
        if isfolder(paths.resultDir)
            movefile(paths.resultDir,fullfile(archiveDir,char(paths.name)));
        end
    otherwise
        error('pipeline:CollisionPolicy','Unknown collision policy.');
end
end

