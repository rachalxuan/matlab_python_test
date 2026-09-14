%% QPSK + representative FEC sweep on the new channel MAT files
% Short integration screen:
%   - fixed QPSK, 30 Msym/s, 8 input samples/symbol
%   - normalized H, noise OFF, CFO/phase/delay = 0
%   - same 2-sps adaptive fractional equalizer for every FEC case
%   - one run for each of CDL A1..A4 and each representative code
%
% Results remain in:
%   NewChannelFECRepresentativeResults
%   NewChannelFECRepresentativeLogs
%
% The selected rates are deliberately representative, not a complete
% code-rate waterfall.  4D-TCM and differential NRZ are excluded here:
% 4D-TCM is a joint coded-modulation waveform, while NRZ-M/NRZ-S is line
% coding rather than a ChannelCoding value.

if exist('NewChannelFECRepresentativeOptions','var') && ...
        isstruct(NewChannelFECRepresentativeOptions)
    representativeUserOptions = NewChannelFECRepresentativeOptions;
else
    representativeUserOptions = struct();
end

sweepFile = [ ...
    'E:/web_code/react/fft_project/react-fft/tmp/' ...
    'codex_new_channel_psd_sync_sweep_v1.m'];

channelDir = [ ...
    'C:\Users\admin\xwechat_files\wxid_95czmz1vt20422_de63\msg\file\' ...
    '2026-09\mat文件\mat文件'];

% Include an uncoded reference, then every ordinary TM code family.
% This representative table currently uses the shortened TPC 1/2 x8
% profile.  Caller overrides can select 2/3 x4 without editing the file.
fecNames = [ ...
    "none (reference)"
    "convolutional 1/2"
    "RS 223/255"
    "RS223 + convolutional 1/2"
    "LDPC 1/2, K=1024"
    "Turbo 1/2, K=3568"
    "TPC 2/3, blocks=4"
    ];

codingNames = { ...
    'none'
    'convolutional'
    'RS'
    'concatenated'
    'LDPC'
    'Turbo'
    'TPC'
    };

% Information-frame byte setting used by the evaluator.  TPC may recompute
% its ordinary-TM frame size from TPCCodeRate/TPCBlocksPerTF.
tfBytes = [1115 1115 223 223 1115 1115 1115];

fecExtra = { ...
    struct()
    struct('ConvolutionalCodeRate','1/2')
    struct('RSMessageLength',223, ...
        'RSInterleavingDepth',1, ...
        'IsRSMessageShortened',false)
    struct('RSMessageLength',223, ...
        'RSInterleavingDepth',1, ...
        'IsRSMessageShortened',false, ...
        'ConvolutionalCodeRate','1/2')
    struct('CodeRate','1/2', ...
        'NumBitsInInformationBlock',1024, ...
        'IsLDPCOnSMTF',false)
    struct('CodeRate','1/2', ...
        'NumBitsInInformationBlock',3568)
    struct('TPCCodeRate','1/2', ...
        'TPCBlocksPerTF',8, ...
        'TPCInterleaver','auto', ...
        'TPCUseKnownZeroConstraint',false, ...
        'TPCDecoderMode','iterative')
    };

if numel(fecNames) ~= numel(codingNames) || ...
        numel(fecNames) ~= numel(tfBytes) || ...
        numel(fecNames) ~= numel(fecExtra)
    error('codex_new_channel_psd_fec_representative_sweep:BadCaseTable', ...
        'FEC case definition lengths do not agree.');
end

startFEC = 1;
if isfield(representativeUserOptions,'StartFEC') && ...
        ~isempty(representativeUserOptions.StartFEC)
    startFEC = max(1,round(double( ...
        representativeUserOptions.StartFEC)));
end
maxFEC = inf;
if isfield(representativeUserOptions,'MaxFEC') && ...
        ~isempty(representativeUserOptions.MaxFEC)
    maxFEC = double(representativeUserOptions.MaxFEC);
end
if startFEC > numel(fecNames) || ~isscalar(maxFEC) || ...
        isnan(maxFEC) || maxFEC <= 0
    error('codex_new_channel_psd_fec_representative_sweep:BadFECSelection', ...
        'StartFEC/MaxFEC does not select a valid FEC case.');
end
if isinf(maxFEC)
    stopFEC = numel(fecNames);
else
    stopFEC = min(numel(fecNames),startFEC+floor(maxFEC)-1);
end
selectedFEC = startFEC:stopFEC;

fprintf('Representative FEC cases selected: %d:%d of %d\n', ...
    startFEC,stopFEC,numel(fecNames));
allRows = cell(numel(selectedFEC),1);
allLogs = cell(numel(selectedFEC),1);

for iSelectedFEC = 1:numel(selectedFEC)
    ic = selectedFEC(iSelectedFEC);
    caseExtra = fecExtra{ic};
    caseName = fecNames(ic);
    configuredInterleaver = "N/A";
    if strcmpi(codingNames{ic},'TPC')
        % Allow a command-line TPC A/B test without editing this file.
        % These fields are applied after the representative defaults so the
        % displayed label and the parameters delivered to TX/RX cannot diverge.
        tpcOptionNames = {'TPCCodeRate','TPCBlocksPerTF', ...
            'TPCInterleaver','TPCUseKnownZeroConstraint', ...
            'TPCDecoderMode'};
        for kTPC = 1:numel(tpcOptionNames)
            optionName = tpcOptionNames{kTPC};
            if isfield(representativeUserOptions,optionName) && ...
                    ~isempty(representativeUserOptions.(optionName))
                caseExtra.(optionName) = ...
                    representativeUserOptions.(optionName);
            end
        end
        configuredInterleaver = localTPCInterleaverMode( ...
            caseExtra.TPCInterleaver,caseExtra.TPCCodeRate);
        caseName = "TPC " + string(caseExtra.TPCCodeRate) + ...
            ", blocks=" + string(caseExtra.TPCBlocksPerTF) + ...
            ", interleaver=" + configuredInterleaver;
    end
    fprintf('\n\n====================================================\n');
    fprintf(' FEC case %d/%d: %s\n',ic,numel(fecNames),caseName);
    fprintf('====================================================\n');

    rx = struct( ...
        'channelPathPowerMode','embedded', ...
        'adaptiveEqualizerSamplingMode','2sps', ...
        'adaptiveFractionalEqualizerTaps',129, ...
        'adaptiveFractionalEqualizerStep',2e-4, ...
        'adaptiveFractionalEqualizerWeightUpdatePeriod',1, ...
        'adaptiveFractionalPostMode','off');

    % Merge caller-provided common receiver settings first.  The nested
    % sweep script intentionally uses a generic variable named userOptions,
    % so this wrapper must keep its own options under a distinct name.
    if isfield(representativeUserOptions,'ReceiverOverrides')
        commonRx = representativeUserOptions.ReceiverOverrides;
        commonRxNames = fieldnames(commonRx);
        for k = 1:numel(commonRxNames)
            rx.(commonRxNames{k}) = commonRx.(commonRxNames{k});
        end
    end

    % FEC-specific fields are authoritative for this case.
    names = fieldnames(caseExtra);
    for k = 1:numel(names)
        rx.(names{k}) = caseExtra.(names{k});
    end

    % Keep a common frame-count screen.  Sixteen warm-up frames is used so
    % A3's observed FSE acquisition transient is not counted as steady BER.
    opts = struct( ...
        'ChannelDir',channelDir, ...
        'FilePattern','*.mat', ...
        'StartFile',1, ...
        'MaxFiles',4, ...
        'ModType','QPSK', ...
        'ChannelCoding',codingNames{ic}, ...
        'NumBytesInTransferFrame',tfBytes(ic), ...
        'SymbolRate',30e6, ...
        'SamplesPerSymbol',8, ...
        'BERWarmUpFrames',16, ...
        'BERFrames',16, ...
        'NoiseMode','off', ...
        'NormalizeHChannel',true, ...
        'ChannelSampleRateHz',1e5, ...
        'ReceiverOverrides',rx, ...
        'VerboseReceiverLog',false, ...
        'SaveCSV',false);

    % Allow a caller to override common test settings.  The coding identity,
    % frame length and composed ReceiverOverrides are restored afterward.
    overrideNames = fieldnames(representativeUserOptions);
    for k = 1:numel(overrideNames)
        if ~any(strcmp(overrideNames{k}, ...
                {'ReceiverOverrides','StartFEC','MaxFEC', ...
                 'TPCCodeRate','TPCBlocksPerTF','TPCInterleaver', ...
                 'TPCUseKnownZeroConstraint','TPCDecoderMode'}))
            opts.(overrideNames{k}) = ...
                representativeUserOptions.(overrideNames{k});
        end
    end
    opts.ChannelCoding = codingNames{ic};
    opts.NumBytesInTransferFrame = tfBytes(ic);
    opts.ReceiverOverrides = rx;

    NewChannelPSDSweepOptions = opts;
    run(sweepFile);
    T = NewChannelPSDSweepResults;
    actualTXCoding = localTXCoding(NewChannelPSDSweepLogs{1});
    fprintf('Requested/actual TX coding: %s / %s\n', ...
        string(codingNames{ic}),actualTXCoding);
    if strlength(actualTXCoding) > 0 && ...
            ~strcmpi(actualTXCoding,string(codingNames{ic}))
        error('codex_new_channel_psd_fec_representative_sweep:TXCodingMismatch', ...
            'Requested coding %s but transmitter reported %s.', ...
            string(codingNames{ic}),actualTXCoding);
    end
    T.FEC = repmat(caseName,height(T),1);
    T.ActualTXCoding = repmat(actualTXCoding,height(T),1);
    T.ConfiguredRate = repmat(localRateLabel(codingNames{ic},caseExtra),height(T),1);
    T.ConfiguredK = repmat(localKLabel(codingNames{ic},caseExtra),height(T),1);
    T.ConfiguredInterleaver = repmat(configuredInterleaver,height(T),1);
    allRows{iSelectedFEC} = T;
    allLogs{iSelectedFEC} = NewChannelPSDSweepLogs;
end

NewChannelFECRepresentativeResults = vertcat(allRows{:});
NewChannelFECRepresentativeLogs = vertcat(allLogs{:});

fprintf('\n\n================ QPSK REPRESENTATIVE FEC @ 30 Msym/s ================\n');
displayVars = {'FileIndex','Family','Profile','FEC', ...
    'ActualTXCoding','ConfiguredRate','ConfiguredK', ...
    'ConfiguredInterleaver', ...
    'CoarseCFOEstimate_Hz','PSKCoarseCFOAttempted', ...
    'PSKCoarseCFOAccepted','PSKCoarseCFOConsistentWindows', ...
    'PSKCoarseCFOWindowCount','PSKCoarseCFOReason', ...
    'BER','FER','CountedFrames', ...
    'FrameErrors','FSEErrorMSE','EqualizerOutputAccepted', ...
    'PredecoderSteadyBER','PredecoderFrameBERP95', ...
    'PredecoderFrameBERMax','PredecoderASMAligned', ...
    'CarrierAvailable','TimingAvailable','FrameAvailable', ...
    'CarrierLock_pct','TimingLock_pct','FrameLock_pct', ...
    'CarrierLockedAtEnd','TimingLockedAtEnd','FrameLockedAtEnd', ...
    'FrameLosses','FrameReacquisitions','Verdict'};
disp(NewChannelFECRepresentativeResults(:,displayVars));

fprintf('\n按 FEC 和判定结果汇总：\n');
disp(groupsummary(NewChannelFECRepresentativeResults,{'FEC','Verdict'}));
fprintf(['\nNo files were written; results are in ', ...
    'NewChannelFECRepresentativeResults and logs in ', ...
    'NewChannelFECRepresentativeLogs.\n']);

function label = localRateLabel(coding,extra)
switch lower(string(coding))
    case "none"
        label = "N/A";
    case "convolutional"
        label = string(extra.ConvolutionalCodeRate);
    case {"rs","concatenated"}
        if isfield(extra,'ConvolutionalCodeRate')
            label = "RS223 + conv " + string(extra.ConvolutionalCodeRate);
        else
            label = "223/255";
        end
    case {"ldpc","turbo"}
        label = string(extra.CodeRate);
    case "tpc"
        label = string(extra.TPCCodeRate) + " x" + string(extra.TPCBlocksPerTF);
    otherwise
        label = "";
end
end

function coding = localTXCoding(logText)
token = regexp(logText,'\[TX\s+([^\]]+)\]','tokens','once');
if isempty(token)
    coding = "";
else
    coding = string(token{1});
end
end

function label = localKLabel(coding,extra)
if isfield(extra,'NumBitsInInformationBlock')
    label = string(extra.NumBitsInInformationBlock);
elseif strcmpi(coding,'RS') || strcmpi(coding,'concatenated')
    label = "223 bytes";
elseif strcmpi(coding,'TPC')
    label = string(extra.TPCBlocksPerTF) + " blocks";
else
    label = "N/A";
end
end

function mode = localTPCInterleaverMode(rawMode,rateLabel)
mode = lower(strtrim(string(rawMode)));
switch mode
    case {"auto","default"}
        if strcmpi(string(rateLabel),"1/2")
            mode = "block";
        else
            mode = "none";
        end
    case {"none","off","bypass"}
        mode = "none";
    case {"block","codeword","on"}
        mode = "block";
    otherwise
        error('codex_new_channel_psd_fec_representative_sweep:BadTPCInterleaver', ...
            'Unsupported TPCInterleaver="%s".',string(rawMode));
end
end
