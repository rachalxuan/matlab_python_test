function T = run_split_receiver_migration_smoke(opts)
%RUN_SPLIT_RECEIVER_MIGRATION_SMOKE Compare coordinator and legacy split RX.
%
%   T = RUN_SPLIT_RECEIVER_MIGRATION_SMOKE() runs a short no-H comparison
%   for QPSK, OQPSK, 16QAM and unequal UQPSK.  It resets the RNG before
%   each coordinator/legacy pair, so a mismatch is structural rather than
%   a different random payload/noise realization.
%
%   T = RUN_SPLIT_RECEIVER_MIGRATION_SMOKE(struct('Profile','withRS'))
%   additionally runs 32QAM + RS to exercise the periodic per-rail ASM
%   alignment migrated into HelperCCSDSTMSplitReceiver.
%
%   EvaluationOverrides is a scalar struct whose fields are applied to
%   every case after the deterministic no-H base configuration.  This is
%   intended for a coordinator-vs-legacy H-channel comparison, for example
%   enableHChannel/equalizer settings, SNR and synchronization impairments.

    if nargin < 1 || isempty(opts)
        opts = struct();
    end
    profile = lower(string(localField(opts, 'Profile', 'core')));
    failOnMismatch = logical(localField(opts, 'FailOnMismatch', true));
    baseSeed = double(localField(opts, 'BaseSeed', 20260731));
    warmUpFrames = max(1, round(double(localField(opts, 'BERWarmUpFrames', 2))));
    berFrames = max(3, round(double(localField(opts, 'BERFrames', 6))));
    evaluationOverrides = localField(opts, 'EvaluationOverrides', struct());
    if ~isstruct(evaluationOverrides) || ~isscalar(evaluationOverrides)
        error('run_split_receiver_migration_smoke:InvalidEvaluationOverrides', ...
            'EvaluationOverrides must be a scalar struct.');
    end

    cases = localCases(profile);
    rows = repmat(localEmptyRow(), numel(cases), 1);

    for k = 1:numel(cases)
        c = cases(k);
        p = localBaseOptions(c, warmUpFrames, berFrames);
        p = localApplyOverrides(p, evaluationOverrides);

        rng(baseSeed + k - 1, 'twister');
        p.UseSplitReceiverCoordinator = true;
        [coordinator, ~] = run_ccsds_tm_evaluation(p);

        rng(baseSeed + k - 1, 'twister');
        p.UseSplitReceiverCoordinator = false;
        [legacy, ~] = run_ccsds_tm_evaluation(p);

        comparison = localCompare(coordinator, legacy);
        rows(k).CaseId = c.Id;
        rows(k).Modulation = c.Modulation;
        rows(k).Coding = c.Coding;
        rows(k).DataPathMode = c.DataPathMode;
        rows(k).CoordinatorBER = localNumeric(coordinator, 'BER');
        rows(k).LegacyBER = localNumeric(legacy, 'BER');
        rows(k).CoordinatorLock_pct = 100*localNumeric(coordinator, 'LockRate');
        rows(k).LegacyLock_pct = 100*localNumeric(legacy, 'LockRate');
        rows(k).CoordinatorFER = localNumeric(coordinator, 'FER');
        rows(k).LegacyFER = localNumeric(legacy, 'FER');
        rows(k).CoordinatorImpl = string(localField( ...
            coordinator, 'SplitReceiverImplementation', 'missing'));
        rows(k).LegacyImpl = string(localField( ...
            legacy, 'SplitReceiverImplementation', 'missing'));
        rows(k).Match = comparison.Match;
        rows(k).Reason = comparison.Reason;
    end

    T = struct2table(rows);
    disp(T);
    fprintf('\nSplitReceiver migration smoke (%s): PASS=%d FAIL=%d\n', ...
        profile, nnz(T.Match), nnz(~T.Match));

    if failOnMismatch && any(~T.Match)
        failed = strjoin(cellstr(T.CaseId(~T.Match)), ', ');
        error('run_split_receiver_migration_smoke:Mismatch', ...
            'Coordinator and legacy outputs differ: %s', failed);
    end
end

function cases = localCases(profile)
    cases = struct( ...
        'Id', { ...
            "splitrx.qpsk.conv12", ...
            "splitrx.oqpsk.conv12", ...
            "splitrx.16qam.conv12", ...
            "splitrx.uqpsk.conv12"}, ...
        'Modulation', {'QPSK','OQPSK','16QAM','UQPSK'}, ...
        'Coding', {'convolutional','convolutional','convolutional','convolutional'}, ...
        'DataPathMode', {'dualIQ','dualIQ','dualIQ','unequalDualIQ'}, ...
        'Rate', {'1/2','1/2','1/2','1/2'});
    if profile == "withrs" || profile == "full"
        cases(end+1) = struct( ...
            'Id', "splitrx.32qam.rs223255", ...
            'Modulation', '32QAM', ...
            'Coding', 'RS', ...
            'DataPathMode', 'dualIQ', ...
            'Rate', '223/255');
    elseif profile ~= "core"
        error('run_split_receiver_migration_smoke:InvalidProfile', ...
            'Profile must be core, withRS, or full.');
    end
end

function p = localBaseOptions(c, warmUpFrames, berFrames)
    p = struct( ...
        'modType', c.Modulation, ...
        'symbolRate', 1e6, ...
        'sps', 4, ...
        'snr', 100, ...
        'cfo', 0, ...
        'phaseOffset', 0, ...
        'delay', 0, ...
        'channelCoding', c.Coding, ...
        'RandomizerEnabled', false, ...
        'RandomizerFECPosition', 'afterEncoding', ...
        'DataPathMode', c.DataPathMode, ...
        'hasASM', true, ...
        'enableHChannel', false, ...
        'enableEqualizer', false, ...
        'berWarmUpFrames', warmUpFrames, ...
        'berFrames', berFrames, ...
        'showFigures', false, ...
        'splitPathDebug', false);
    if strcmpi(c.Coding, 'convolutional')
        p.ConvolutionalCodeRate = c.Rate;
    elseif strcmpi(c.Coding, 'RS')
        p.RSMessageLength = 223;
    end
    if strcmpi(c.Modulation, 'UQPSK')
        p.RRatio = 2;
        p.ARatio = 2;
        p.carrierRecoveryMode = 'uqpsk-teacher';
        p.enableUQPSKFFTCoarseCFO = true;
    end
end

function comparison = localCompare(coordinator, legacy)
    fields = {'BER','LockRate','FER','I_BER','I_LockRate','I_FER', ...
        'Q_BER','Q_LockRate','Q_FER','CountedFrames','MatchedFrames', ...
        'DecodedFrames'};
    comparison = struct('Match',true,'Reason',"");
    if ~logical(localField(coordinator, 'success', false)) || ...
            ~logical(localField(legacy, 'success', false))
        comparison.Match = false;
        comparison.Reason = "one implementation returned success=false";
        return;
    end
    if ~strcmpi(string(localField(coordinator, ...
            'SplitReceiverImplementation', '')), "coordinator") || ...
            ~strcmpi(string(localField(legacy, ...
            'SplitReceiverImplementation', '')), "legacy")
        comparison.Match = false;
        comparison.Reason = "implementation marker missing or incorrect";
        return;
    end
    for k = 1:numel(fields)
        field = fields{k};
        a = localNumeric(coordinator, field);
        b = localNumeric(legacy, field);
        if ~(isequaln(a,b) || (isfinite(a) && isfinite(b) && abs(a-b) <= 1e-12))
            comparison.Match = false;
            comparison.Reason = "metric differs: " + string(field);
            return;
        end
    end
    comparison.Reason = "identical metrics";
end

function value = localField(s, name, defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    end
end

function value = localNumeric(s, name)
    value = localField(s, name, NaN);
    if isempty(value)
        value = NaN;
    elseif ischar(value) || isstring(value)
        value = str2double(string(value));
    end
    value = double(value);
    if ~isscalar(value)
        value = NaN;
    end
end

function target = localApplyOverrides(target, overrides)
    names = fieldnames(overrides);
    for k = 1:numel(names)
        name = names{k};
        target.(name) = overrides.(name);
    end
end

function row = localEmptyRow()
    row = struct( ...
        'CaseId', "", ...
        'Modulation', "", ...
        'Coding', "", ...
        'DataPathMode', "", ...
        'CoordinatorBER', NaN, ...
        'LegacyBER', NaN, ...
        'CoordinatorLock_pct', NaN, ...
        'LegacyLock_pct', NaN, ...
        'CoordinatorFER', NaN, ...
        'LegacyFER', NaN, ...
        'CoordinatorImpl', "", ...
        'LegacyImpl', "", ...
        'Match', false, ...
        'Reason', "");
end
