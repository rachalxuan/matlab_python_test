%% PSK acquisition and same-tap CMA/DD validation (no artifacts written)
% PSKFSEValidationOptions.Stage = 'cfo' | 'dual' | 'frozen'
% Optional: FileIndices (0=No-H), ModTypes, TargetDuration_s,
% WarmupDuration_s, CFOHz. All non-CFO impairments are held fixed.
% CFO stage: 8PSK + RS223; dual/frozen: uncoded QPSK/8PSK.
% A zero measured BER is an integration result, not a BER<1e-6 certificate.

vfOpts = struct();
if exist('PSKFSEValidationOptions','var') && isstruct(PSKFSEValidationOptions)
    vfOpts = PSKFSEValidationOptions;
end
assert(isscalar(vfOpts), ...
    'PSKFSEValidationOptions must be a scalar struct; use string arrays for ModTypes.');
vfStage = lower(string(vfGet(vfOpts,'Stage','dual')));
switch vfStage
    case 'cfo'
        vfDefaultFiles = [2 4];
        vfDefaultMods = "8PSK";
        vfModes = "2sps";
        vfDefaultCFO = [0 2e5 -2e5 1e6 -1e6];
        vfHResponses = "normal";
        vfCoding = 'RS';
        vfTFBytes = 223;
        vfChannelBitsPerFrame = 255*8+32;
    case {'dual','frozen'}
        vfDefaultFiles = [0 2 3 4];
        vfDefaultMods = ["QPSK" "8PSK"];
        vfModes = ["2sps" "2sps-dual"];
        vfDefaultCFO = 0;
        vfHResponses = "normal";
        if vfStage == "frozen"
            vfDefaultFiles = [3 4];
            vfHResponses = ["frozen" "normal"];
        end
        vfCoding = 'none';
        vfTFBytes = 1115;
        vfChannelBitsPerFrame = 1115*8+32;
    otherwise
        error('PSKFSEValidation:Stage','Stage must be cfo, dual, or frozen.');
end
vfFiles = reshape(double(vfGet(vfOpts,'FileIndices',vfDefaultFiles)),1,[]);
vfMods = reshape(upper(string(vfGet(vfOpts,'ModTypes',vfDefaultMods))),1,[]);
vfCFOList = reshape(double(vfGet(vfOpts,'CFOHz',vfDefaultCFO)),1,[]);
vfDuration = double(vfGet(vfOpts,'TargetDuration_s',0.004));
vfWarmup = double(vfGet(vfOpts,'WarmupDuration_s',0.0015));
assert(isscalar(vfDuration) && isfinite(vfDuration) && ...
    isscalar(vfWarmup) && isfinite(vfWarmup) && ...
    vfWarmup >= 0 && vfDuration > vfWarmup, ...
    'TargetDuration_s must exceed the nonnegative WarmupDuration_s.');
assert(all(ismember(vfMods,["BPSK" "QPSK" "8PSK"])), ...
    'ModTypes supports BPSK/QPSK/8PSK only.');
assert(~isempty(vfFiles) && all(isfinite(vfFiles) & vfFiles >= 0 & ...
    vfFiles == round(vfFiles)),'FileIndices must contain nonnegative integers.');
assert(~isempty(vfCFOList) && all(isfinite(vfCFOList)), ...
    'CFOHz must contain finite frequency offsets.');

vfSweepFile = fullfile(fileparts(mfilename('fullpath')), ...
    'codex_new_channel_psd_sync_sweep_v1.m');
vfCount = numel(vfFiles)*numel(vfMods)*numel(vfModes)* ...
    numel(vfCFOList)*numel(vfHResponses);
vfRows = cell(vfCount,1);
PSKFSEValidationLogs = cell(vfCount,1);
vfCase = 0;
fprintf('\nPSK FSE validation: stage=%s, %d cases, target=%.3f ms\n', ...
    vfStage,vfCount,1000*vfDuration);
for vfMod = vfMods
    vfM = 2;
    if vfMod == "QPSK", vfM = 4; end
    if vfMod == "8PSK", vfM = 8; end
    vfFrameDuration = vfChannelBitsPerFrame/(30e6*log2(vfM));
    vfTotalFrames = max(8,ceil(vfDuration/vfFrameDuration));
    vfWarmFrames = ceil(vfWarmup/vfFrameDuration);
    assert(vfTotalFrames-vfWarmFrames >= 4, ...
        'Requested durations leave fewer than four BER frames.');
    for vfFile = vfFiles
        for vfResponse = vfHResponses
            for vfCFO = vfCFOList
                for vfMode = vfModes
                    vfCase = vfCase+1;
                    vfRx = struct( ...
                        'enableHChannel',vfFile ~= 0, ...
                        'channelPathPowerMode','embedded', ...
                        'debugHMatrixResponseMode',char(vfResponse), ...
                        'cfo',vfCFO,'phaseOffset',0,'delay',0, ...
                        'carrierCaptureRangeHz',2e6, ...
                        'adaptiveEqualizerSamplingMode',char(vfMode), ...
                        'adaptiveFractionalEqualizerTaps',129, ...
                        'adaptiveFractionalEqualizerStep',2e-4, ...
                        'adaptiveFractionalEqualizerWeightUpdatePeriod',1, ...
                        'adaptiveFractionalPostMode','off', ...
                        'PSKPostFSEPhaseTrackerMode','off', ...
                        'collectPredecoderStats',true, ...
                        'debugCarrierRecovery',true, ...
                        'debugAdaptiveEqualizer',true);
                    if strcmp(vfCoding,'RS')
                        vfRx.RSMessageLength = 223;
                        vfRx.RSInterleavingDepth = 1;
                        vfRx.IsRSMessageShortened = false;
                    end
                    NewChannelPSDSweepOptions = struct( ...
                        'StartFile',max(vfFile,1),'MaxFiles',1, ...
                        'ModType',char(vfMod),'ChannelCoding',vfCoding, ...
                        'NumBytesInTransferFrame',vfTFBytes, ...
                        'SymbolRate',30e6,'SamplesPerSymbol',8, ...
                        'BERWarmUpFrames',vfWarmFrames, ...
                        'BERFrames',vfTotalFrames-vfWarmFrames, ...
                        'NoiseMode','off','NormalizeHChannel',true, ...
                        'Seed',364232726,'ReceiverOverrides',vfRx, ...
                        'VerboseReceiverLog',false,'SaveCSV',false);
                    vfWrapperLog = evalc('run(vfSweepFile);');
                    vfRow = NewChannelPSDSweepResults(1,:);
                    vfRow.TestModType = vfMod;
                    vfRow.TestCoding = string(vfCoding);
                    vfRow.TestMode = vfMode;
                    vfRow.TestHResponse = vfResponse;
                    vfRow.TestCFO_Hz = vfCFO;
                    vfRow.ConfiguredWarmupFrames = vfWarmFrames;
                    vfRow.ConfiguredBERFrames = vfTotalFrames-vfWarmFrames;
                    if vfFile == 0
                        vfRow.Profile = "No-H";
                        vfRow.FileIndex = 0;
                        vfRow.FileName = "";
                    end
                    % In an uncoded test payload BER is already pre-FEC BER.
                    vfRow.ComparisonPreFECBER = vfRow.PredecoderSteadyBER;
                    if strcmp(vfCoding,'none')
                        vfRow.ComparisonPreFECBER = vfRow.BER;
                    end
                    vfRows{vfCase} = vfRow;
                    PSKFSEValidationLogs{vfCase} = NewChannelPSDSweepLogs{1};
                    fprintf(['[%d/%d] %s %s %s %s CFO=%+.0f | ', ...
                        'BER=%.6g FER=%.6g switch=%d lock=%.2f%%\n'], ...
                        vfCase,vfCount,vfMod,vfRow.Profile,vfResponse,vfMode, ...
                        vfCFO,vfRow.BER,vfRow.FER,vfRow.FSEDualSwitchApplied, ...
                        vfRow.FrameLock_pct);
                end
            end
        end
    end
end
PSKFSEValidationResults = vertcat(vfRows{:});
disp(PSKFSEValidationResults(:,{ ...
    'TestModType','TestCoding','Profile','TestHResponse','TestMode', ...
    'TestCFO_Hz','WaveformDuration_s','BER','FER','ComparisonPreFECBER', ...
    'CountedFrames','PSKCoarseCFOAccepted','PostFSECFOAccepted', ...
    'TotalCFOCorrection_Hz','FSEDualSwitchApplied', ...
    'FSEDualAcceptance_pct','FSEDualDDMSE','FrameLock_pct','Verdict'}));
fprintf(['Logs: PSKFSEValidationLogs. No files written. ', ...
    'No-H/A2 are regression controls; a switch or CFO vote alone is not a pass.\n']);

function value = vfGet(s,name,defaultValue)
value = defaultValue;
if isfield(s,name) && ~isempty(s.(name)), value = s.(name); end
end
