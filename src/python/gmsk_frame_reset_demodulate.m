function [softBits, info, rawMetric] = gmsk_frame_reset_demodulate(inputData, cfg)
%GMSK_FRAME_RESET_DEMODULATE ASM-aided GMSK precode-state recovery.
%
% This helper keeps the complex-symbol differential detector continuous, but
% resolves the CCSDS GMSK precode state independently at every frame.  It is
% intentionally opt-in; the legacy receiver remains the default path.
%
% Required cfg fields:
%   framePeriodBits  Number of GMSK precode-input bits per coded frame.
%   asmTemplates     Known ASM bit template(s), one template per column.
%
% Optional cfg fields:
%   asmOffsetBits    Unknown coded ASM prefix before asmTemplates (default 0).
%   inputIsRawMetric Treat inputData as an already computed raw metric.
%   knownFrameStart  One-based raw-metric index of a frame boundary.
%   knownAltPhase    Alternating-mask phase, 0 or 1.
%   asmMaxErrors     Maximum accepted ASM Hamming errors.
%   asmMinGap        Required error gap between the two state hypotheses.
%   maxSearchFrames  Periodic ASM instances used during grid search.
%   minSearchFrames  Minimum instances required during grid search.
%   printDebug       Print one diagnostic line per recovered frame.

% Soft-value convention matches HelperCCSDSTMDemodulator's GMSK branch:
% bit 0 -> positive, bit 1 -> negative.

% The helper does not reset the complex-symbol memory at frame boundaries.
% Only the CCSDS precode data state is re-established from the ASM.

% This is an experimental receiver mode.  A rejected ASM produces one
% zero-soft frame (an erasure), after which the next frame is tested afresh.

% Copyright (c) project contributors.

    if nargin < 2 || isempty(cfg)
        cfg = struct();
    end
    cfg = localDefaults(cfg);
    inputData = inputData(:);

    if cfg.inputIsRawMetric
        rawMetric = double(real(inputData));
    else
        rawMetric = localRawMetric(inputData);
    end

    info = localEmptyInfo();
    info.FramePeriodBits = cfg.framePeriodBits;
    info.ASMOffsetBits = cfg.asmOffsetBits;
    info.ASMTemplateLength = size(cfg.asmTemplates, 1);
    info.RawMetricLength = numel(rawMetric);

    knownEnd = cfg.asmOffsetBits + size(cfg.asmTemplates, 1);
    if numel(rawMetric) < knownEnd
        softBits = zeros(0, 1);
        info.FailureReason = 'raw metric is shorter than the ASM search prefix';
        return;
    end

    if isempty(cfg.knownFrameStart)
        [frameStart, altPhase, grid] = localFindFrameGrid(rawMetric, cfg);
    else
        frameStart = round(double(cfg.knownFrameStart));
        if isempty(cfg.knownAltPhase)
            [altPhase, grid] = localChooseAltPhase(rawMetric, frameStart, cfg);
        else
            altPhase = mod(round(double(cfg.knownAltPhase)), 2);
            grid = localScoreGrid(rawMetric, frameStart, altPhase, cfg);
        end
    end

    info.FrameStart = frameStart;
    info.AltPhase = altPhase;
    info.GridMedianASMErrors = grid.MedianError;
    info.GridMeanASMErrors = grid.MeanError;
    info.GridWorstASMErrors = grid.WorstError;
    info.GridFramesScored = grid.FramesScored;
    info.GridFound = frameStart >= 1 && grid.FramesScored >= cfg.minSearchFrames && ...
        grid.MedianError <= cfg.asmMaxErrors;

    if ~info.GridFound
        softBits = zeros(0, 1);
        info.FailureReason = sprintf( ...
            'periodic ASM grid not found (median %.2f, frames %d)', ...
            grid.MedianError, grid.FramesScored);
        return;
    end

    lastFullStart = numel(rawMetric) - cfg.framePeriodBits + 1;
    if frameStart > lastFullStart
        softBits = zeros(0, 1);
        info.GridFound = false;
        info.FailureReason = 'ASM found, but no complete frame remains';
        return;
    end

    frameStarts = (frameStart:cfg.framePeriodBits:lastFullStart).';
    numFrames = numel(frameStarts);
    softBits = zeros(numFrames * cfg.framePeriodBits, 1);

    info.FrameStarts = frameStarts;
    info.FrameIndex = (1:numFrames).';
    info.ASMErrorsState0 = inf(numFrames, 1);
    info.ASMErrorsState1 = inf(numFrames, 1);
    info.ASMGap = zeros(numFrames, 1);
    info.SelectedInitialState = -ones(numFrames, 1);
    info.SelectedFinalState = -ones(numFrames, 1);
    info.SelectedASMTemplate = zeros(numFrames, 1);
    info.FrameAccepted = false(numFrames, 1);
    info.Reacquired = false(numFrames, 1);
    info.RawMetricRMS = zeros(numFrames, 1);

    previousAccepted = false;
    for frameIndex = 1:numFrames
        rawStart = frameStarts(frameIndex);
        rawStop = rawStart + cfg.framePeriodBits - 1;
        rawFrame = rawMetric(rawStart:rawStop);

        [soft0, final0] = localInverse(rawFrame, false, rawStart-1, altPhase);
        [soft1, final1] = localInverse(rawFrame, true, rawStart-1, altPhase);

        templateRange = cfg.asmOffsetBits + (1:size(cfg.asmTemplates, 1));
        [err0, template0] = localBestTemplateError(soft0(templateRange), cfg.asmTemplates);
        [err1, template1] = localBestTemplateError(soft1(templateRange), cfg.asmTemplates);

        if err0 < err1
            selectedState = 0;
            selectedSoft = soft0;
            selectedFinal = final0;
            selectedTemplate = template0;
        elseif err1 < err0
            selectedState = 1;
            selectedSoft = soft1;
            selectedFinal = final1;
            selectedTemplate = template1;
        else
            selectedState = -1;
            selectedSoft = zeros(size(rawFrame));
            selectedFinal = -1;
            selectedTemplate = 0;
        end

        bestErr = min(err0, err1);
        gap = abs(err0 - err1);
        accepted = selectedState >= 0 && bestErr <= cfg.asmMaxErrors && ...
            gap >= cfg.asmMinGap;

        if accepted
            % The known template ends at the end of the (possibly coded)
            % ASM.  Re-seed the payload inversion from that known last bit,
            % so an ASM decision error cannot poison the whole payload.
            if knownEnd < cfg.framePeriodBits
                lastKnownBit = logical(cfg.asmTemplates(end, selectedTemplate));
                payloadRaw = rawFrame(knownEnd+1:end);
                [payloadSoft, selectedFinal] = localInverse( ...
                    payloadRaw, lastKnownBit, rawStart+knownEnd-1, altPhase);
                selectedSoft(knownEnd+1:end) = payloadSoft;
            end

            outRange = (frameIndex-1)*cfg.framePeriodBits + ...
                (1:cfg.framePeriodBits);
            softBits(outRange) = max(min(selectedSoft, 20), -20);
        end

        info.ASMErrorsState0(frameIndex) = err0;
        info.ASMErrorsState1(frameIndex) = err1;
        info.ASMGap(frameIndex) = gap;
        info.SelectedInitialState(frameIndex) = selectedState;
        info.SelectedFinalState(frameIndex) = selectedFinal;
        info.SelectedASMTemplate(frameIndex) = selectedTemplate;
        info.FrameAccepted(frameIndex) = accepted;
        info.Reacquired(frameIndex) = frameIndex > 1 && accepted && ~previousAccepted;
        info.RawMetricRMS(frameIndex) = sqrt(mean(rawFrame.^2) + eps);

        if cfg.printDebug
            fprintf(['[GMSK frame reset] frame=%03d rawStart=%d, ', ...
                'asmErr(0/1)=%d/%d, gap=%d, state=%d, accepted=%d\n'], ...
                frameIndex, rawStart, err0, err1, gap, selectedState, accepted);
        end
        previousAccepted = accepted;
    end

    info.TotalFrames = numFrames;
    info.AcceptedFrames = nnz(info.FrameAccepted);
    info.FailureReason = '';
end

function rawMetric = localRawMetric(u)
    u = u(:);
    if isempty(u)
        rawMetric = zeros(0, 1);
        return;
    end

    % The very first value has no previous received symbol and is therefore
    % deliberately zero.  Periodic ASM acquisition normally starts at the
    % first complete frame after the receiver transient.
    previous = [u(1); u(1:end-1)];
    phaseDifference = angle(u .* conj(previous));
    confidence = abs(u) .* abs(previous);
    rawMetric = -sin(phaseDifference) .* confidence;
    scale = sqrt(mean(rawMetric.^2) + eps);
    rawMetric = 5 * double(rawMetric) / scale;
end

function [frameStart, altPhase, bestGrid] = localFindFrameGrid(rawMetric, cfg)
    knownEnd = cfg.asmOffsetBits + size(cfg.asmTemplates, 1);
    maxStart = min(cfg.framePeriodBits, numel(rawMetric)-knownEnd+1);
    frameStart = -1;
    altPhase = 0;
    bestGrid = localWorstGrid();

    for phase = 0:1
        streamSoft = localInverse(rawMetric, false, 0, phase);
        streamBits = streamSoft < 0;
        for candidateStart = 1:maxStart
            grid = localScoreGridBits(streamBits, candidateStart, cfg);
            if localGridIsBetter(grid, bestGrid)
                bestGrid = grid;
                frameStart = candidateStart;
                altPhase = phase;
            end
        end
    end
end

function [altPhase, bestGrid] = localChooseAltPhase(rawMetric, frameStart, cfg)
    altPhase = 0;
    bestGrid = localWorstGrid();
    for phase = 0:1
        grid = localScoreGrid(rawMetric, frameStart, phase, cfg);
        if localGridIsBetter(grid, bestGrid)
            bestGrid = grid;
            altPhase = phase;
        end
    end
end

function grid = localScoreGrid(rawMetric, frameStart, altPhase, cfg)
    streamSoft = localInverse(rawMetric, false, 0, altPhase);
    grid = localScoreGridBits(streamSoft < 0, frameStart, cfg);
end

function grid = localScoreGridBits(streamBits, frameStart, cfg)
    templateLength = size(cfg.asmTemplates, 1);
    templateStart = frameStart + cfg.asmOffsetBits;
    errors = zeros(0, 1);

    for frameIndex = 0:cfg.maxSearchFrames-1
        first = templateStart + frameIndex * cfg.framePeriodBits;
        last = first + templateLength - 1;
        if first < 1 || last > numel(streamBits)
            break;
        end

        segment = streamBits(first:last);
        best = inf;
        for templateIndex = 1:size(cfg.asmTemplates, 2)
            template = logical(cfg.asmTemplates(:, templateIndex));
            e = nnz(segment ~= template);
            % The unknown precode data state makes the other hypothesis the
            % complement of this decoded segment.
            best = min(best, min(e, templateLength-e));
        end
        errors(end+1, 1) = best; %#ok<AGROW>
    end

    if isempty(errors)
        grid = localWorstGrid();
        return;
    end

    grid = struct();
    grid.MedianError = median(errors);
    grid.MeanError = mean(errors);
    grid.WorstError = max(errors);
    grid.BestError = min(errors);
    grid.FramesScored = numel(errors);
end

function better = localGridIsBetter(candidate, current)
    tolerance = 1e-12;
    better = candidate.FramesScored > 0 && ...
        (candidate.MedianError < current.MedianError - tolerance || ...
        (abs(candidate.MedianError-current.MedianError) <= tolerance && ...
         candidate.MeanError < current.MeanError - tolerance) || ...
        (abs(candidate.MedianError-current.MedianError) <= tolerance && ...
         abs(candidate.MeanError-current.MeanError) <= tolerance && ...
         candidate.BestError < current.BestError));
end

function grid = localWorstGrid()
    grid = struct('MedianError', inf, 'MeanError', inf, ...
        'WorstError', inf, 'BestError', inf, 'FramesScored', 0);
end

function [bestError, bestTemplate] = localBestTemplateError(soft, templates)
    hard = soft(:) < 0;
    bestError = inf;
    bestTemplate = 0;
    for templateIndex = 1:size(templates, 2)
        thisError = nnz(hard ~= logical(templates(:, templateIndex)));
        if thisError < bestError
            bestError = thisError;
            bestTemplate = templateIndex;
        end
    end
end

function [soft, finalState] = localInverse(raw, initialState, streamStartIndex, altPhase)
    raw = double(raw(:));
    soft = zeros(size(raw));
    lastDecoded = logical(initialState);

    for k = 1:numel(raw)
        streamIndex = streamStartIndex + k;
        metric = raw(k);
        if mod(streamIndex + altPhase, 2) == 1
            metric = -metric;
        end
        if lastDecoded
            metric = -metric;
        end
        soft(k) = metric;
        lastDecoded = metric < 0;
    end
    finalState = lastDecoded;
end

function cfg = localDefaults(cfg)
    if ~isfield(cfg, 'framePeriodBits') || isempty(cfg.framePeriodBits)
        if isfield(cfg, 'encodedFrameBits') && ~isempty(cfg.encodedFrameBits)
            cfg.framePeriodBits = cfg.encodedFrameBits;
        else
            error('gmsk_frame_reset_demodulate:MissingFramePeriod', ...
                'cfg.framePeriodBits is required.');
        end
    end
    if ~isfield(cfg, 'asmTemplates') || isempty(cfg.asmTemplates)
        if isfield(cfg, 'asmBits') && ~isempty(cfg.asmBits)
            cfg.asmTemplates = cfg.asmBits(:);
        else
            cfg.asmTemplates = localHexToBits('1ACFFC1D');
        end
    end
    if ~isfield(cfg, 'asmOffsetBits') || isempty(cfg.asmOffsetBits)
        cfg.asmOffsetBits = 0;
    end
    if ~isfield(cfg, 'inputIsRawMetric') || isempty(cfg.inputIsRawMetric)
        cfg.inputIsRawMetric = false;
    end
    if ~isfield(cfg, 'knownFrameStart')
        cfg.knownFrameStart = [];
    end
    if ~isfield(cfg, 'knownAltPhase')
        cfg.knownAltPhase = [];
    end
    templateLength = size(cfg.asmTemplates, 1);
    if ~isfield(cfg, 'asmMaxErrors') || isempty(cfg.asmMaxErrors)
        cfg.asmMaxErrors = max(2, ceil(0.20 * templateLength));
    end
    if ~isfield(cfg, 'asmMinGap') || isempty(cfg.asmMinGap)
        cfg.asmMinGap = max(3, ceil(0.25 * templateLength));
    end
    if ~isfield(cfg, 'maxSearchFrames') || isempty(cfg.maxSearchFrames)
        cfg.maxSearchFrames = 8;
    end
    if ~isfield(cfg, 'minSearchFrames') || isempty(cfg.minSearchFrames)
        cfg.minSearchFrames = 2;
    end
    if ~isfield(cfg, 'printDebug') || isempty(cfg.printDebug)
        cfg.printDebug = false;
    end

    cfg.framePeriodBits = round(double(cfg.framePeriodBits));
    cfg.asmOffsetBits = round(double(cfg.asmOffsetBits));
    cfg.asmTemplates = logical(cfg.asmTemplates);
    cfg.asmMaxErrors = max(0, round(double(cfg.asmMaxErrors)));
    cfg.asmMinGap = max(0, round(double(cfg.asmMinGap)));
    cfg.maxSearchFrames = max(1, round(double(cfg.maxSearchFrames)));
    cfg.minSearchFrames = max(1, round(double(cfg.minSearchFrames)));
    cfg.inputIsRawMetric = logical(cfg.inputIsRawMetric);
    cfg.printDebug = logical(cfg.printDebug);

    if cfg.framePeriodBits <= 0 || cfg.asmOffsetBits < 0 || ...
            cfg.asmOffsetBits + size(cfg.asmTemplates, 1) > cfg.framePeriodBits
        error('gmsk_frame_reset_demodulate:InvalidConfiguration', ...
            'Frame period and ASM template/offset configuration are inconsistent.');
    end
end

function info = localEmptyInfo()
    info = struct();
    info.GridFound = false;
    info.FrameStart = -1;
    info.AltPhase = 0;
    info.GridMedianASMErrors = inf;
    info.GridMeanASMErrors = inf;
    info.GridWorstASMErrors = inf;
    info.GridFramesScored = 0;
    info.FramePeriodBits = 0;
    info.ASMOffsetBits = 0;
    info.ASMTemplateLength = 0;
    info.RawMetricLength = 0;
    info.FrameStarts = zeros(0, 1);
    info.FrameIndex = zeros(0, 1);
    info.ASMErrorsState0 = zeros(0, 1);
    info.ASMErrorsState1 = zeros(0, 1);
    info.ASMGap = zeros(0, 1);
    info.SelectedInitialState = zeros(0, 1);
    info.SelectedFinalState = zeros(0, 1);
    info.SelectedASMTemplate = zeros(0, 1);
    info.FrameAccepted = false(0, 1);
    info.Reacquired = false(0, 1);
    info.RawMetricRMS = zeros(0, 1);
    info.TotalFrames = 0;
    info.AcceptedFrames = 0;
    info.FailureReason = '';
end

function bits = localHexToBits(hexValue)
    hexValue = upper(char(hexValue));
    bits = false(4*numel(hexValue), 1);
    out = 1;
    for k = 1:numel(hexValue)
        value = hex2dec(hexValue(k));
        bits(out:out+3) = logical(bitget(uint8(value), 4:-1:1).');
        out = out + 4;
    end
end
