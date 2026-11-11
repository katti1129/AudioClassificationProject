function batch = background_batch_config()
%BACKGROUND_BATCH_CONFIG Default Cartesian sweep; no changes to acoustics.
% Input: none. Output: horizontal CPA distances [m], Source speeds [km/h],
% shared simultaneous geometric CPA time [s], Source horizontal heading [deg].
batch.distancesM=[5,10,20,40];
batch.sourceSpeedsKmh=[20,40,60];
batch.cpaTimeSec=4;
batch.sourceHeadingDeg=0;
end
