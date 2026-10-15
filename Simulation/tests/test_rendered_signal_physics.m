function checks = test_rendered_signal_physics(o)
%TEST_RENDERED_SIGNAL_PHYSICS Measure generated pressure, not solver labels.
% Input: validation options. Output: PASS/FAIL rows with independent targets.
% Inputs are 3 s tones and an isolated impulse, pressure amplitude [Pa].
% Exercises existing synthesis functions at 16 kHz; output/WAV and real-WAV
% full-pipeline behavior are tested separately by ambulance scenarios.
fs=o.fs;t=(0:round(o.toneDurationSec*fs)-1)'/fs;
x=sin(2*pi*o.toneFrequencyHz*t);c=default_config();speed=c.physics.soundSpeedMps;
entity=@(p,v)struct('initialPositionM',p,'initialVelocityMps',v,'accelerationMps2',[0 0 0]);
s=entity([0 0 1.5],[0 0 0]); r=entity([10 0 1.5],[0 0 0]);
p=acoustics.solveDirectPath(s,r,t,speed,c.solver);
y10=acoustics.synthesizeDirect(x,t,p,1,.5,true(size(t)));
r.initialPositionM(1)=20;p20=acoustics.solveDirectPath(s,r,t,speed,c.solver);
y20=acoustics.synthesizeDirect(x,t,p20,1,.5,true(size(t)));
steady=t>=.7&t<=2.5;
level=20*log10(rms(y10(steady))/rms(y20(steady)));
checks=researchtest.check('synthetic','distance_doubling',level,20*log10(2),o.levelToleranceDb,'dB','Output RMS; steady interval 0.7 to 2.5 s');
checks=[checks;researchtest.check('synthetic','absolute_spreading', ...
    20*log10(rms(y10(steady))/rms(x(steady))),-20,o.levelToleranceDb,'dB','1 Pa tone at 1 m, receiver 10 m')];
% Impulse at 0.5 s; record extends beyond both direct and reflected arrivals.
pulse=zeros(size(t));pulse(round(.5*fs)+1)=1;
yp=acoustics.synthesizeDirect(pulse,t,p,1,.5,true(size(t)));
[~,ix]=max(abs(yp));
checks=[checks;researchtest.check('synthetic','direct_arrival',t(ix),.5+10/speed,o.delayToleranceSec,'s','Peak timing, including fractional-delay interpolation')];
% Independent collinear constant-velocity Doppler formula.
velocities=[20 0;0 -15;20 -15];
for k=1:3
    ss=entity([-100 0 1.5],[velocities(k,1) 0 0]);
    rr=entity([0 0 1.5],[velocities(k,2) 0 0]);
    path=acoustics.solveDirectPath(ss,rr,t,speed,c.solver);
    y=acoustics.synthesizeDirect(x,t,path,1,.5,true(size(t)));
    observed=zeroCrossFrequency(y(steady),t(steady));
    expected=o.toneFrequencyHz*(speed-velocities(k,2))/(speed-velocities(k,1));
    checks=[checks;researchtest.check('synthetic',"doppler_case_"+k,observed,expected,o.frequencyToleranceHz,'Hz','Frequency estimated from rendered upward zero crossings')]; %#ok<AGROW>
end
% Ground mirror geometry: endpoints (0,0,1), (4,0,1); length sqrt(20).
ss=entity([0 0 1],[0 0 0]);rr=entity([4 0 1],[0 0 0]);
plane=c.reflection.planes;plane.pressureReflectionCoefficient=.6;
[~,reflection]=acoustics.synthesizeReflections(x,t,ss,rr,t,plane,speed,c.solver,1,.5,struct([]),.01);
checks=[checks;researchtest.check('synthetic','reflection_gain', ...
    20*log10(rms(reflection(steady))/rms(x(steady))),20*log10(.6/sqrt(20)),o.levelToleranceDb,'dB','Independent image-source length and pressure reflection coefficient')];
[~,reflectionPulse]=acoustics.synthesizeReflections(pulse,t,ss,rr,t,plane,speed,c.solver,1,.5,struct([]),.01);
[~,ix]=max(abs(reflectionPulse));
checks=[checks;researchtest.check('synthetic','reflection_arrival',t(ix),.5+sqrt(20)/speed,o.delayToleranceSec,'s','Ground-reflected impulse peak')];
% Symmetric box, side route via y=+/-1 is shorter than top route.
% Independent path-equivalent approximation target, NOT an exact box solution.
ss=entity([0 0 1.5],[0 0 0]);rr=entity([20 0 1.5],[0 0 0]);
b=researchtest.box(1,[10 0],1,2,4);L=2*sqrt(9.5^2+1)+1;delta=L-20;
c.simulation.durationSec=o.toneDurationSec;c.audio.processingSampleRateHz=fs;
c.diffraction.unsupportedMultiplePathAction="error";
observedLoss=zeros(size(o.lossFrequenciesHz));
for k=1:numel(o.lossFrequenciesHz)
    f=o.lossFrequenciesHz(k);tone=sin(2*pi*f*t);
    [y,d]=acoustics.synthesizeDiffraction(tone,t,ss,rr,t,b,true,c);
    v=2*sqrt(f*delta/speed);
    expectedLoss=6.9+20*log10(sqrt((v-.1)^2+1)+v-.1);
    observedLoss(k)=-20*log10(rms(y(steady))/(rms(tone(steady))/20));
    checks=[checks;researchtest.check('synthetic',"diffraction_loss_"+f,observedLoss(k),expectedLoss,o.diffractionToleranceDb,'dB','Checks implemented magnitude-only path-equivalent model, not experimental validity')]; %#ok<AGROW>
end
save(fullfile(o.runDir,'synthetic_measurements.mat'),'t','x','y10','y20','pulse','yp','reflection','reflectionPulse','observedLoss','d');
end

function f = zeroCrossFrequency(y,t)
%ZEROCROSSFREQUENCY Linear crossing times [s] -> mean frequency [Hz].
i=find(y(1:end-1)<=0 & y(2:end)>0);
if numel(i)<3,f=NaN;return;end
cross=t(i)-y(i).*(t(i+1)-t(i))./(y(i+1)-y(i));
f=(numel(cross)-1)/(cross(end)-cross(1));
end
