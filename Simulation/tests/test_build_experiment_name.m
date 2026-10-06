function tests = test_build_experiment_name()
%TEST_BUILD_EXPERIMENT_NAME Verify names are derived from actual config.
tests=functiontests(localfunctions);
end
function test_example(tc)
c=default_config();
rows=pipeline.default_conditions(1,c);
rows.CPA_m=20; rows.SourceVelocityKmh=60; rows.ReceiverVelocityKmh=4;
rows.GroundReflectionCoeff=.8; rows.ObstacleCount=24; rows.Seed=1;
c=pipeline.row_to_config(rows,c);
name=pipeline.build_experiment_name(c);
verifyTrue(tc,startsWith(name, ...
    "ambulance_CPA20m_V060_RV4_R080_OBS1_N24_SEED1_DIF1_REF1_H"));
verifyFalse(tc,contains(name,"_PV"));
verifyEqual(tc,c.receiver.initialVelocityMps,[4/3.6 0 0],'AbsTol',1e-12);
verifyEqual(tc,c.receiver.initialPositionM(2),20);
verifyEqual(tc,[c.obstacle.materials.pressureReflectionCoefficient],[.8 .7 .6]);
end
function test_identityIncludesHiddenPhysicalSettings(tc)
c=default_config(); name=pipeline.build_experiment_name(c);
c.source.initialPositionM(3)=2;
verifyNotEqual(tc,pipeline.build_experiment_name(c),name);
c=default_config(); c.output.rootDir='a_different_folder';
verifyEqual(tc,pipeline.build_experiment_name(c),name);
c.receiver.initialVelocityMps(1)=-4/3.6;
verifyTrue(tc,contains(pipeline.build_experiment_name(c),"_RVm4_"));
end
function test_mappingAndValidation(tc)
c=default_config(); rows=pipeline.default_conditions(3,c);
rows=pipeline.assign_seeds(rows,40);
verifyEqual(tc,rows.Seed,[40;41;42]);
rows.Seed(2)=40; verifyEqual(tc,rows.Seed(2),40);
common=rows(1,:); common.CPA_m=50;
rows=pipeline.apply_common(rows,common,[1 3]);
verifyEqual(tc,rows.CPA_m,[50;10;50]);
verifyEqual(tc,rows.Seed,[40;40;42]);
verifyError(tc,@()pipeline.assign_seeds(rows,2^32-2),'pipeline:SeedOverflow');
common.SourceAccelerationMps2=1;
verifyError(tc,@()pipeline.row_to_config(common,c),'pipeline:ProfileAcceleration');
common.Profile="constant_acceleration";
mapped=pipeline.row_to_config(common,c);
verifyEqual(tc,mapped.source.accelerationMps2,[1 0 0]);
end
function test_noInventedGroundPlane(tc)
c=default_config(); c.reflection.planes=struct([]);
row=pipeline.default_conditions(1,c);
verifyTrue(tc,isnan(row.GroundReflectionCoeff));
mapped=pipeline.row_to_config(row,c);
verifyEmpty(tc,mapped.reflection.planes);
row.GroundReflectionCoeff=.8;
verifyError(tc,@()pipeline.row_to_config(row,c),'pipeline:NoGroundPlane');
end
