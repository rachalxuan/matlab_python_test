function T = sweep_apsk_pilotless_wide_capture(userOpt)
%SWEEP_APSK_PILOTLESS_WIDE_CAPTURE Isolated pilotless APSK CFO regression.
%
%   T = sweep_apsk_pilotless_wide_capture()
%   T = sweep_apsk_pilotless_wide_capture(userOpt)
%
% This test does not modify or depend on the main evaluator defaults. Every
% row starts from a fresh apskPilotlessDefaultConfig instance and explicitly
% enables the experimental 32APSK inner+middle-ring x^12 coarse estimator.
% The common second-order DD loop is optional and OFF by default because the
% feed-forward BPS path is already sufficient for static NoH CFO capture.

if nargin < 1 || isempty(userOpt)
    userOpt = struct();
end

opt = struct( ...
    'modTypes',{{'16APSK','32APSK'}}, ...
    'cfoHz',[-2e6 -1e6 0 1e6 2e6], ...
    'symbolRate',50e6, ...
    'sps',8, ...
    'NumFrames',20, ...
    'NumBytesInTransferFrame',256, ...
    'BERWarmUpFrames',6, ...
    'noiseMode','psd', ...
    'noisePSDdBmHz',-115.3, ...
    'inputLevelDbm',-10, ...
    'MaxSteadyBER',1e-5, ...
    'enableCommonSecondOrderLoop',false, ...
    'debug',false, ...
    'randomSeed',20260825);
opt = localMerge(opt,userOpt);

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(thisDir);
addpath(rootDir);
addpath(thisDir);

rows = cell(numel(opt.modTypes)*numel(opt.cfoHz),13);
r = 0;
for im = 1:numel(opt.modTypes)
    modulation = char(string(opt.modTypes{im}));
    for ic = 1:numel(opt.cfoHz)
        r = r + 1;
        cfg = apskPilotlessDefaultConfig();
        cfg.modType = modulation;
        cfg.symbolRate = opt.symbolRate;
        cfg.sps = opt.sps;
        cfg.NumFrames = opt.NumFrames;
        cfg.NumBytesInTransferFrame = opt.NumBytesInTransferFrame;
        cfg.BERWarmUpFrames = opt.BERWarmUpFrames;
        cfg.cfo = opt.cfoHz(ic);
        cfg.noiseMode = opt.noiseMode;
        cfg.noisePSDdBmHz = opt.noisePSDdBmHz;
        cfg.inputLevelDbm = opt.inputLevelDbm;
        cfg.Debug = logical(opt.debug);
        cfg.DebugReceiver = logical(opt.debug);
        cfg.RandomSeed = opt.randomSeed + 1000*im + ic;

        cfg.CarrierRecovery.MaxAcquisitionCFOHz = 2e6;
        cfg.CarrierRecovery.EnableWideRangeRingCoarseCFO = true;
        cfg.CarrierRecovery.CoarseUseInnerMiddleRings = true;
        cfg.CarrierRecovery.CoarsePowerOrder = 12;
        cfg.CarrierRecovery.EnableDDPhaseTracker = ...
            logical(opt.enableCommonSecondOrderLoop);
        cfg.CarrierRecovery.UseCommonSecondOrderLoop = ...
            logical(opt.enableCommonSecondOrderLoop);
        cfg.CarrierRecovery.Debug = logical(opt.debug);

        fprintf('[APSK wide capture %02d/%02d] %s CFO=%+.3f MHz\n', ...
            r,size(rows,1),modulation,opt.cfoHz(ic)/1e6);
        try
            if opt.debug
                R = run_apsk_pilotless_receiver(cfg);
            else
                evalc('R = run_apsk_pilotless_receiver(cfg);');
            end
            capturePass = R.ASMQualified && ...
                R.BERSteady <= opt.MaxSteadyBER && ...
                strcmpi(R.FinalCarrierState,'TRACK');
            rows(r,:) = {string(modulation),opt.cfoHz(ic), ...
                R.FourthPowerCFO_Hz, ...
                R.FourthPowerCFO_Hz-opt.cfoHz(ic), ...
                R.BERSteady,R.EVMSteady_pct,R.MERSteady_dB, ...
                R.DDAcceptance_pct,R.DDPhaseErrorRMS_deg, ...
                R.AcquisitionFramesApprox,R.ASMQualified, ...
                logical(capturePass),string(R.Status)};
        catch ME
            rows(r,:) = {string(modulation),opt.cfoHz(ic),NaN,NaN, ...
                NaN,NaN,NaN,NaN,NaN,NaN,false,false, ...
                "ERROR: " + string(ME.message)};
        end
    end
end

T = cell2table(rows,'VariableNames',{ ...
    'ModType','RequestedCFO_Hz','EstimatedCFO_Hz','CFOError_Hz', ...
    'SteadyBER','SteadyEVM_pct','SteadyMER_dB','DDAcceptance_pct', ...
    'DDPhaseRMS_deg','AcquisitionFramesApprox','ASMQualified', ...
    'CapturePass','StandaloneStrictStatus'});
disp(T);
end

function out = localMerge(out,user)
if ~isstruct(user)
    error('sweep_apsk_pilotless_wide_capture:InvalidOptions', ...
        'userOpt must be a struct.');
end
names = fieldnames(user);
for k = 1:numel(names)
    out.(names{k}) = user.(names{k});
end
end
