function options = research_validation_config()
%RESEARCH_VALIDATION_CONFIG Settings for read-only diagnosis and new test runs.
% Output: OPTIONS; time [s], frequency [Hz], pressure [Pa], distance [m].
% Tolerances are numerical test criteria, NOT claims of measured accuracy.
root=fileparts(fileparts(mfilename('fullpath')));
options.projectRoot=root;
options.inputWav=fullfile(root,'data','input','ambulance.wav');
options.datasetDir=fullfile(root,'datasets','Dataset_001');
options.outputParent=fullfile(root,'data','output','research_validation');
options.runSavedDataset=true;
options.runPhysics=true;
options.runAmbulance=true;
options.fs=16000;
options.toneDurationSec=3;
options.toneFrequencyHz=800;
options.lossFrequenciesHz=[500 1000 2000];
options.observationDurationSec=10;
options.geometryStepSec=.01;
% Two audio samples allow discrete peak selection and interpolation error.
options.delayToleranceSec=2/options.fs;
% Finite 1.8 s observation gives ~0.56 Hz nominal frequency resolution.
options.frequencyToleranceHz=.6;
options.levelToleranceDb=.2;
% WOLA/windowing/interpolation error allowance for the implemented
% magnitude-only, path-equivalent knife-edge approximation, not true UTD.
options.diffractionToleranceDb=.5;
options.warpTolerance=.002;
% Gate metrics are warnings; no unvalidated psychoacoustic click threshold.
options.gateNumericalFloorPa=1e-7;
options.saveFigures=true;
end
