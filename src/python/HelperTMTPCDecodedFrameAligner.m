function [alignedBits, info] = HelperTMTPCDecodedFrameAligner( ...
        decodedBits, bitsPerFrame, validFrameIds, varargin)
%HELPERTMTPCDECODEDFRAMEALIGNER Guarded post-decoder TPC frame alignment.
%   This helper is intentionally separate from the TPC decoder.  The raw ASM
%   synchronizer in HelperCCSDSTMDecoder remains the primary frame boundary
%   detector.  This routine may only replace that boundary when the current
%   boundary is not confirmed and another bit phase produces a strictly
%   longer run of consecutively increasing TM VC frame counts.
%
%   A count of frame IDs that merely occur in VALIDFRAMEIDS is not sufficient:
%   an incorrect bit phase can sample a constant payload byte (commonly zero)
%   at the VCFC position and create many false "matches".  Requiring modulo-256
%   increments rejects such repeated-ID false locks.

    p = inputParser;
    p.FunctionName = mfilename;
    addParameter(p, 'MinConsecutiveFrames', 3, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 2);
    addParameter(p, 'MinCandidateConsecutiveFrames', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 2);
    addParameter(p, 'MaxShiftBits', bitsPerFrame-1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'Debug', false, @(x) islogical(x) || isnumeric(x));
    parse(p, varargin{:});

    bits = int8(decodedBits(:) ~= 0);
    bitsPerFrame = round(double(bitsPerFrame));
    if bitsPerFrame < 32
        error('HelperTMTPCDecodedFrameAligner:FrameTooShort', ...
            'bitsPerFrame must be at least 32 to contain the TM VCFC.');
    end

    validFrameIds = unique(round(double(validFrameIds(:))));
    validFrameIds = validFrameIds(validFrameIds >= 0 & validFrameIds <= 255);
    validLookup = true(256, 1);
    if ~isempty(validFrameIds)
        validLookup(:) = false;
        validLookup(validFrameIds + 1) = true;
    end

    minConsecutive = max(2, round(double(p.Results.MinConsecutiveFrames)));
    minCandidateConsecutive = max(minConsecutive, ...
        round(double(p.Results.MinCandidateConsecutiveFrames)));
    maxShift = min([bitsPerFrame-1, round(double(p.Results.MaxShiftBits)), ...
        max(0, numel(bits)-bitsPerFrame)]);

    baseline = localScoreShift(bits, bitsPerFrame, 0, validLookup);
    best = baseline;
    searched = false;

    % Once the decoder boundary is confirmed by a consecutive VCFC run, do
    % not search thousands of alternative bit phases.  This both prevents a
    % false overwrite and removes the dominant cost of the old TPC scan.
    if baseline.MaxRun < minConsecutive
        searched = true;
        for shift = 1:maxShift
            candidate = localScoreShift(bits, bitsPerFrame, shift, validLookup);
            if localIsBetter(candidate, best)
                best = candidate;
            end
        end
    end

    % Exhaustively scanning an entire 16200-bit TPC frame creates many
    % chance runs of length 3 or 4 in a garbage stream.  A replacement
    % boundary therefore needs both an absolute floor and evidence spanning
    % a substantial fraction of the decoded frames.  The decoder's own
    % shift-zero boundary remains the preferred reference.
    requiredCandidateRun = max(minCandidateConsecutive, ...
        ceil(0.40*best.NumFrames));
    applied = searched && best.Shift > 0 && ...
        best.MaxRun >= requiredCandidateRun && ...
        best.MaxRun > baseline.MaxRun;
    if applied
        alignedBits = decodedBits(best.Shift+1:end);
        reason = "strictly-better-consecutive-run";
    else
        alignedBits = decodedBits;
        if baseline.MaxRun >= minConsecutive
            reason = "baseline-confirmed";
        elseif best.MaxRun < requiredCandidateRun
            reason = "no-candidate-confirmed";
        else
            reason = "candidate-not-strictly-better";
        end
    end

    info = struct( ...
        'Applied', applied, ...
        'SelectedShift', double(applied) * best.Shift, ...
        'CandidateShift', best.Shift, ...
        'BaselineMatched', baseline.Matched, ...
        'BaselineMaxRun', baseline.MaxRun, ...
        'BaselineIncrements', baseline.Increments, ...
        'BaselineUniqueIds', baseline.UniqueIds, ...
        'CandidateMatched', best.Matched, ...
        'CandidateMaxRun', best.MaxRun, ...
        'CandidateIncrements', best.Increments, ...
        'CandidateUniqueIds', best.UniqueIds, ...
        'MinConsecutiveFrames', minConsecutive, ...
        'MinCandidateConsecutiveFrames', minCandidateConsecutive, ...
        'RequiredCandidateRun', requiredCandidateRun, ...
        'SearchedAlternativeShifts', searched, ...
        'Reason', reason);

    if logical(p.Results.Debug)
        fprintf(['   [TPC ALIGN] baseline shift=0 matched=%d run=%d ', ...
            'increments=%d unique=%d\n'], ...
            baseline.Matched, baseline.MaxRun, baseline.Increments, ...
            baseline.UniqueIds);
        fprintf(['   [TPC ALIGN] candidate shift=%d matched=%d run=%d ', ...
            'increments=%d unique=%d requiredRun=%d; applied=%d reason=%s\n'], ...
            best.Shift, best.Matched, best.MaxRun, best.Increments, ...
            best.UniqueIds,requiredCandidateRun,applied,char(reason));
    end
end

function score = localScoreShift(bits, bitsPerFrame, shift, validLookup)
    numFrames = floor((numel(bits)-shift) / bitsPerFrame);
    ids = zeros(numFrames, 1);
    valid = false(numFrames, 1);
    weights = 2.^(7:-1:0).';

    % Only read VCFC bits 25:32.  The previous implementation copied every
    % complete 16200-bit TPC frame for every trial shift.
    for iFrame = 1:numFrames
        headerStart = shift + (iFrame-1)*bitsPerFrame + 25;
        vcfc = double(bits(headerStart:headerStart+7));
        ids(iFrame) = vcfc.' * weights;
        valid(iFrame) = validLookup(ids(iFrame)+1);
    end

    matched = nnz(valid);
    increments = 0;
    maxRun = 0;
    run = 0;
    lastId = NaN;
    for iFrame = 1:numFrames
        if ~valid(iFrame)
            run = 0;
            lastId = NaN;
            continue;
        end
        if isfinite(lastId) && ids(iFrame) == mod(lastId + 1, 256)
            run = run + 1;
            increments = increments + 1;
        else
            run = 1;
        end
        maxRun = max(maxRun, run);
        lastId = ids(iFrame);
    end

    score = struct( ...
        'Shift', shift, ...
        'NumFrames', numFrames, ...
        'Matched', matched, ...
        'MaxRun', maxRun, ...
        'Increments', increments, ...
        'UniqueIds', numel(unique(ids(valid))));
end

function tf = localIsBetter(candidate, current)
    % Evidence strength follows receiver semantics: periodic/continuous
    % progression first, broad ID coverage second, raw membership last.
    lhs = [candidate.MaxRun, candidate.Increments, candidate.UniqueIds, ...
        candidate.Matched, -candidate.Shift];
    rhs = [current.MaxRun, current.Increments, current.UniqueIds, ...
        current.Matched, -current.Shift];
    firstDifferent = find(lhs ~= rhs, 1, 'first');
    tf = ~isempty(firstDifferent) && lhs(firstDifferent) > rhs(firstDifferent);
end
