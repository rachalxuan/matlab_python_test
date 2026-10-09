function outputFile=test_apsk_bps_trajectory(scope)
% Regression of BPS state ownership. No truth in either receiver.
% core: fixed failed/control/default cases. cfo: positive/negative true CFO.
% seed: one independent seed at 10 dB. apsk32: normal operating point.
% h: historical H non-regression (not necessarily complete acceptance).
if nargin<1, scope='core'; end
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
addpath(fullfile(root,'src','python','apsk_pilotless_stage2_asm'));
d=load(fullfile(root,'tmp','APSK_NoiseModeCompare_20261008_104234_192.mat'));
if strcmp(scope,'core')
    cases=[2 7 5 10]; cfoList=0;
elseif strcmp(scope,'cfo')
    cases=[5 10]; cfoList=[-150e3 150e3];
elseif strcmp(scope,'apsk32')
    cases=[5 10]; cfoList=0;
elseif strcmp(scope,'h')
    cases=[16 32]; cfoList=0;
elseif strcmp(scope,'seed')
    cases=[2 7]; cfoList=0;
else
    error('Unknown scope.');
end
rows={}; logs={};
for ci=cases
for cfo=cfoList
    if strcmp(scope,'h')
        h=load(fullfile(root,'tmp','tp55c9efcc_a166_4a1c_bcb9_f355bdd95780', ...
            sprintf('%dAPSK_H.mat',ci)),'p');
        p=h.p;
    else
        p=d.NoiseTestInputs{ci};
    end
    p.cfo=cfo;
    if strcmp(scope,'apsk32'), p.modType='32APSK'; end
    if strcmp(scope,'seed'), p.randomSeed=20260927; end
    p.captureBaselineData=true; p.debugSynchronizationChain=true;
    p.enableReceiverTimeline=true; p.enableRuntimeLockTelemetry=true;
    modes=["legacy","trusted-slope"];
    if strcmp(scope,'core'), modes=["legacy","trusted-slope","default"]; end
    for mode=modes
        % Override ONLY the trajectory, not the H-specific BPS defaults.
        if mode=="default"
            p.PilotlessAPSKCarrierRecovery=rmfield(p.PilotlessAPSKCarrierRecovery, ...
                'BlindPhaseSearchTrajectoryMode');
        else
            p.PilotlessAPSKCarrierRecovery.BlindPhaseSearchTrajectoryMode=char(mode);
        end
        rng(p.randomSeed,'twister');
        logText=evalc('r=run_ccsds_tm_evaluation(p);');
        assert(r.success,'%s',logText);
        c=r.BaselineCapture;
        if mode=="legacy"
            baseline=c;
            if cfo==0 && strcmp(scope,'core')
                expected=d.NoiseTestResults(ci,:);
                assert(isequaln(r.BER,expected.BER) && isequaln(r.FER,expected.FER) && ...
                    r.MeasurementCoverage.ComparedFrames==expected.Compared, ...
                    'Legacy failed to reproduce historical baseline.');
            end
        else
            assert(isequaln(c.TxWaveform,baseline.TxWaveform));
            assert(isequaln(c.CoarseSynchronizedWaveform,baseline.CoarseSynchronizedWaveform));
            assert(isequaln(c.TimeSynchronizedSymbols,baseline.TimeSynchronizedSymbols));
        end
        bs=c.PulseStageCapture.PilotlessState.Carrier.BlindPhaseSearch;
        if mode~="legacy"
            oldbs=baseline.PulseStageCapture.PilotlessState.Carrier.BlindPhaseSearch;
            assert(isequaln(bs.MeasuredPhaseModuloRad,oldbs.MeasuredPhaseModuloRad));
            assert(isequaln(bs.BestMetric,oldbs.BestMetric));
            assert(isequaln(bs.Reliable,oldbs.Reliable));
        end
        if mode=="trusted-slope"
            newPilot=c.PulseStageCapture.PilotlessOutput;
        elseif mode=="default"
            assert(strcmp(bs.TrajectoryMode,'trusted-slope'));
            assert(isequaln(newPilot,c.PulseStageCapture.PilotlessOutput));
        end
        % No per-window truth rotations. For zero-CFO test, original timing
        % stream has known physical phase; compare corrections modulo ONE
        % constant initial branch, ignoring only the startup prefix.
        phase=bs.PhaseAtCentersRad;
        jumps=nnz(abs(diff(phase))>pi/4);
        row=struct('Case',ci,'Modulation',string(p.modType), ...
            'Pulse',string(p.PulseShapingFilter),'CFO_Hz',cfo, ...
            'Mode',mode,'BER',r.BER,'FER',r.FER, ...
            'Compared',r.MeasurementCoverage.ComparedFrames, ...
            'Expected',r.MeasurementCoverage.ExpectedFrames, ...
            'Complete',r.MeasurementCoverage.Complete, ...
            'RecoveredNotCompared',r.MeasurementCoverage.RecoveredNotComparedFrames, ...
            'MaxBPSFrequency_Hz',max(abs(bs.FrequencyRadPerSymbol))*p.symbolRate/(2*pi), ...
            'LargeSingleHopSteps',jumps);
        rows{end+1}=row; logs{end+1}=logText; %#ok<AGROW>
        disp(struct2table(row));
    end
end
end
Results=struct2table(vertcat(rows{:}));
Results.AcceptancePassed=Results.BER==0 & Results.FER==0 & Results.Complete & ...
    Results.Compared==Results.Expected & Results.RecoveredNotCompared==0;
outputFile=fullfile(root,'tmp',['APSK_BPS_Trajectory_' scope '.mat']);
save(outputFile,'Results','logs','-v7');
disp(Results); fprintf('Report: %s\n',outputFile);
new=Results.Mode=="trusted-slope";
if strcmp(scope,'h')
    old=Results.Mode=="legacy";
    assert(all(Results.BER(new)<=Results.BER(old) & Results.FER(new)<=Results.FER(old) & ...
        Results.Compared(new)>=Results.Compared(old)), 'H regression.');
    fprintf('H comparison is NON-REGRESSION only; AcceptancePassed still flags incomplete coverage.\n');
else
    assert(all(Results.AcceptancePassed(Results.Mode~="legacy")), ...
        'New trajectory did not pass all cases.');
end
end
