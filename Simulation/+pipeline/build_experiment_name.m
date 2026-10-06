function name = build_experiment_name(config)
%BUILD_EXPERIMENT_NAME Create the sole canonical condition/file name.
%   NAME includes WAV stem, horizontal y offset [m], signed initial x
%   velocities [km/h], ground pressure coefficient, obstacle flags/count,
%   seed, diffraction/reflection. H suffix hashes full non-output config.
%   PV is deliberately absent: it is not defined in the existing code.
[~,source]=fileparts(config.audio.inputFile);
source=regexprep(source,'[^A-Za-z0-9_-]','_');
if isempty(source), source='source'; end
source=source(1:min(24,numel(source)));
cpa=abs(config.receiver.initialPositionM(2)-config.source.initialPositionM(2));
p=pipeline.ground_plane_index(config);
coefficient='NA';
if ~isempty(p), coefficient=token(100*config.reflection.planes(p).pressureReflectionCoefficient,3); end
n=0;
if config.obstacle.enabled
    n=config.obstacle.count;
    if ~isempty(config.obstacle.manualObstacles), n=numel(config.obstacle.manualObstacles); end
end
hashConfig=config;
hashConfig.simulation.id="";
hashConfig.output=struct(); % Destination/output switches do not change experiment identity.
hash=erase(acoustics.createSimulationId(hashConfig),"SIM_");
name=string(source)+"_CPA"+token(cpa,0)+"m_V"+ ...
    token(config.source.initialVelocityMps(1)*3.6,3)+"_RV"+ ...
    token(config.receiver.initialVelocityMps(1)*3.6,0)+"_R"+coefficient+ ...
    "_OBS"+string(double(config.obstacle.enabled))+"_N"+string(n)+ ...
    "_SEED"+string(config.obstacle.seed)+"_DIF"+string(double(config.diffraction.enabled))+ ...
    "_REF"+string(double(config.reflection.enabled))+"_H"+hash;
end

function value=token(number,width)
%TOKEN Encode signed decimal numbers using filename-safe m and p.
if abs(number-round(number))<1e-10
    value=sprintf('%0*d',width,abs(round(number)));
else
    value=strrep(sprintf('%.8g',abs(number)),'.','p');
    value=strrep(strrep(value,'+',''),'-','m');
end
if number<0, value=['m',value]; end
value=string(value);
end

