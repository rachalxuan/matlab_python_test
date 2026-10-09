function outputFile = test_apsk_coarse_acquisition(scope)
% Fixed inputs; compare x^48 with the default ring/holdout acquisition.
% Truth is used ONLY for assertions, never passed to the acquisition helper.
% One compact report per scope; no waveforms or receiver captures are saved.
if nargin<1, scope='fixed'; end
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
addpath(fullfile(root,'src','python','apsk_pilotless_stage2_asm'));
d=load(fullfile(root,'tmp','TM_System_awgn_20261008_202837_091.mat'), ...
    'SystemTestInputs');
base=d.SystemTestInputs{43};
cases={};
if strcmp(scope,'fixed')
    for pulse=["root raised cosine","none"]
        for snrDB=[20 15 10 5]
            p=base; p.PulseShapingFilter=char(pulse); p.snr=snrDB;
            cases{end+1}=p; %#ok<AGROW>
        end
    end
elseif strcmp(scope,'regression')
    for modulation=["16APSK","32APSK"]
        for pulse=["root raised cosine","none"]
            for cfo=[-150e3 150e3]
                p=base; p.modType=char(modulation);
                p.PulseShapingFilter=char(pulse); p.snr=20; p.cfo=cfo;
                cases{end+1}=p; %#ok<AGROW>
            end
            p=base; p.modType=char(modulation); p.PulseShapingFilter=char(pulse);
            p.randomSeed=20260927;
            cases{end+1}=p; %#ok<AGROW>
        end
    end
elseif strcmp(scope,'h')
    for order=[16 32]
        h=load(fullfile(root,'tmp','tp55c9efcc_a166_4a1c_bcb9_f355bdd95780', ...
            sprintf('%dAPSK_H.mat',order)),'p');
        cases{end+1}=h.p; %#ok<AGROW>
    end
elseif strcmp(scope,'unit')
    checks=localUnitChecks();
    outputFile=fullfile(root,'tmp','APSK_Coarse_Acquisition_unit.mat');
    save(outputFile,'checks','-v7'); disp(checks); return;
else
    error('Use fixed, regression, h, or unit.');
end
rows={}; logs={};
for k=1:numel(cases)
    p=cases{k}; p.captureBaselineData=true; p.debugPilotlessAPSK=true;
    snrDB=Inf;
    if isfield(p,'snr'), snrDB=p.snr; end
    p.PilotlessAPSKCarrierRecovery.BlindPhaseSearchTrajectoryMode='trusted-slope';
    oldCapture=[];
    for mode=["historical-coarse","default"]
        if mode=="historical-coarse"
            p.PilotlessAPSKCarrierRecovery.EnableWideRangeRingCoarseCFO=false;
        else
            p.PilotlessAPSKCarrierRecovery=rmfield(p.PilotlessAPSKCarrierRecovery, ...
                'EnableWideRangeRingCoarseCFO');
        end
        rng(p.randomSeed,'twister');
        logText=evalc('r=run_ccsds_tm_evaluation(p);');
        row=struct('Case',k,'Modulation',string(p.modType), ...
            'Pulse',string(p.PulseShapingFilter),'Seed',p.randomSeed, ...
            'SNR_dB',snrDB,'ConfiguredCFO_Hz',p.cfo,'Mode',mode, ...
            'Success',logical(r.success),'EstimatedCFO_Hz',NaN, ...
            'HoldoutStatistic',NaN,'BER',NaN,'FER',NaN, ...
            'Compared',0,'Expected',p.berFrames,'RecoveredNotCompared',NaN, ...
            'Complete',false,'SameUpstream',false,'Error',"");
        token=regexp(logText,'x\^M FFT CFO\s*: M=\S+, ([+-]?[\d.]+) Hz','tokens','once');
        if isempty(token)
            token=regexp(logText,'coarse validation\] candidate=([+-]?[\d.]+) Hz','tokens','once');
        end
        if ~isempty(token), row.EstimatedCFO_Hz=str2double(token{1}); end
        token=regexp(logText,'coherentEnergy=([\d.]+)','tokens','once');
        if ~isempty(token), row.HoldoutStatistic=str2double(token{1}); end
        if r.success
            row.BER=r.BER; row.FER=r.FER;
            cv=r.MeasurementCoverage;
            row.Compared=cv.ComparedFrames; row.Expected=cv.ExpectedFrames;
            row.Complete=cv.Complete;
            row.RecoveredNotCompared=cv.RecoveredNotComparedFrames;
            c=r.BaselineCapture;
            if mode=="historical-coarse"
                oldCapture=c;
            elseif ~isempty(oldCapture)
                assert(isequaln(c.TxWaveform,oldCapture.TxWaveform));
                assert(isequaln(c.CoarseSynchronizedWaveform,oldCapture.CoarseSynchronizedWaveform));
                assert(isequaln(c.TimeSynchronizedSymbols,oldCapture.TimeSynchronizedSymbols));
                row.SameUpstream=true;
                if strcmp(p.modType,'16APSK')
                    assert(isequaln(c.FineSynchronizedSymbols,oldCapture.FineSynchronizedSymbols), ...
                        '16APSK receiver output changed.');
                end
            end
        else
            lines=splitlines(string(logText));
            row.Error=strjoin(lines(contains(lines,'ERROR')),' ');
        end
        rows{end+1}=row; logs{end+1}=logText; %#ok<AGROW>
        fprintf('[%d/%d %s] %s %s SNR=%g CFO=%+.1f -> %+.1f Hz, BER=%g FER=%g, %d/%d\n', ...
            k,numel(cases),mode,p.modType,p.PulseShapingFilter,snrDB,p.cfo, ...
            row.EstimatedCFO_Hz,row.BER,row.FER,row.Compared,row.Expected);
        if ~r.success, fprintf('%s\n',row.Error); end
        clear r c;
    end
end
Results=struct2table(vertcat(rows{:}));
Results.ZeroErrorsComplete=Results.Success & Results.Complete & ...
    Results.Compared==Results.Expected & Results.BER==0 & Results.FER==0 & ...
    Results.RecoveredNotCompared==0;
outputFile=fullfile(root,'tmp',['APSK_Coarse_Acquisition_' scope '.mat']);
save(outputFile,'Results','logs','cases','-v7');
fprintf('Report: %s\n',outputFile);
disp(Results(:,{'Case','Modulation','Pulse','SNR_dB','Mode','EstimatedCFO_Hz', ...
    'HoldoutStatistic','BER','Compared','Expected','ZeroErrorsComplete'}));
new=Results.Mode=="default";
if strcmp(scope,'h')
    old=Results.Mode=="historical-coarse";
    assert(all(Results.Success(new)==Results.Success(old)) && ...
        all(Results.Compared(new)>=Results.Compared(old)) && ...
        all(Results.BER(new)<=Results.BER(old)), 'Historical H regression.');
else
    required=new & Results.SNR_dB>=10;
    assert(all(Results.ZeroErrorsComplete(required)), ...
        'Required case failed; report saved. 5 dB is diagnostic, not zero-BER acceptance.');
end
end

function checks=localUnitChecks()
ref=HelperCCSDSFACMReferenceConstellation(21);
radii=unique(round(abs(ref)*1e10)/1e10);
opt=struct('PowerOrder',12,'VerifyOnHoldout',true,'RadiusMax',mean(radii(2:3)), ...
    'MaxCFOHz',200e3,'AcquisitionSymbols',4096);
Rs=30e6; n=(0:4095).'; rng(702,'twister');
x=ref(randi(32,size(n)));
for f=[-150e3 0 150e3]
    [est,info]=HelperTMAPSKFourthPowerCoarseCFO(x.*exp(1j*2*pi*f*n/Rs),Rs,opt);
    assert(info.Qualified && abs(est-f)<100,'Clean CFO unit case failed.');
end
% An excellent tone in the fitting block cannot authorize a different tone
% in held-out samples. This directly tests the false-peak rejection contract.
z=x; z(2049:end)=z(2049:end).*exp(1j*2*pi*100e3*n(2049:end)/Rs);
[~,info]=HelperTMAPSKFourthPowerCoarseCFO(z,Rs,opt);
assert(~info.Qualified && ~info.ValidationQualified);
[~,info]=HelperTMAPSKFourthPowerCoarseCFO(zeros(size(x)),Rs,opt);
assert(~info.Qualified);
z=x; idx=2:2:numel(z);
z(idx)=z(idx).*exp(1j*2*pi*100e3*n(idx)/Rs);
[~,info]=HelperTMAPSKFourthPowerCoarseCFO(z,Rs,opt);
assert(~info.Qualified && nnz(info.CandidateAccepted)>1, ...
    'Two persistent carrier candidates must remain ambiguous.');
% The disabled estimator must not contribute a NaN range tolerance.
cfg=apskPilotlessDefaultConfig(); carrier=cfg.CarrierRecovery;
carrier.SymbolRateHz=Rs; carrier.EnableFourthPowerFFTCoarseCFO=false;
[~,~,info]=HelperTMAPSKCarrierRecovery(x,'32APSK',carrier);
assert(info.AcquisitionQualified && info.AcquisitionRangeTolerance_Hz==0);
checks=struct('CleanCFO',true,'InconsistentToneRejected',true, ...
    'SilenceRejected',true,'AmbiguousTonesRejected',true,'DisabledFFTRangeFinite',true);
end
