function [resolvedSymbols, info] = HelperTMAPSKASMResolver(symbols, modulation, options)
%HELPERTMAPSKASMRESOLVER Resolve 90-deg APSK carrier ambiguity using CCSDS ASM.
%
%   [Y,INFO] = HelperTMAPSKASMResolver(X,MODULATION,OPTIONS)
%
% Purpose
%   This helper is a standalone extraction of the receiver-observable core of
%   run_ccsds_tm_evaluation/selectRotationsByASM for the current pilotless
%   APSK laboratory receiver.  It does NOT use transmitted bits or BER to
%   choose a phase.  It tests the four APSK-equivalent rotations
%
%       0, +90, +180, -90 deg
%
%   demodulates each hypothesis, searches for the CCSDS Attached Sync Marker
%   (ASM), and scores the periodic ASM recurrence.  The best qualified ASM
%   hypothesis selects the ambiguity rotation.
%
% Stage-2 scope
%   * 16APSK / 32APSK
%   * ordinary TM, single stream
%   * ChannelCoding = 'none'
%   * PCMFormat = 'NRZ-L'
%   * default CCSDS TM ASM = hex 1ACFFC1D unless OPTIONS.ASMHex is supplied
%
% This intentionally does NOT pretend to support convolutional/RS/LDPC/Turbo
% yet.  The main evaluator has code-specific ASM templates and offsets; those
% should be extracted later once the uncoded pilotless receiver is verified.
%
% Important output
%   INFO.TrimBits is a receiver-observable bit alignment.  Apply it AFTER the
%   APSK demodulator:
%
%       soft = demodObj(resolvedSymbols);
%       soft = soft(INFO.TrimBits+1:end);
%
%   Do not try to convert TrimBits to a symbol trim in the general case:
%   a TM frame period need not be divisible by 5 bits/symbol for 32APSK.
%
% Key OPTIONS (all optional)
%   ChannelCoding                  default 'none'
%   PCMFormat                     default 'NRZ-L'
%   NumBytesInTransferFrame       default 1115
%   ASMHex                        default '1ACFFC1D'
%   DemodNoiseVariance           default 0.01
%   MaxSearchBits                 default 250000
%   ASMMaxErr                     default 6
%   ASMMinScoreGap                default 4
%   PeriodicCandidates            default 32
%   PeriodicFrames                default 8
%   ASMErrMargin                  default 4
%   AllowASMInversion             default true (matches main evaluator score)
%   RequireQualification          default true
%   Debug                         default false
%
% INFO fields include
%   Applied, Qualified, Reason
%   SelectedRotation_deg, SelectedRotationIndex
%   Scores, BestErrors, MeanErrors, PeriodicFramesByRotation
%   BestPositions, ScoreGap
%   FirstASMBitPosition, TrimBits, PeriodBits, ASMLength
%   SelectedASMInverted
%   HardBitsSelected (search interval only, useful for diagnostics)
%
% This function makes no BER decision and never accesses TX truth.

    if nargin < 3 || isempty(options)
        options = struct();
    end

    x = complex(symbols(:));
    modName = upper(strtrim(char(string(modulation))));

    info = localEmptyInfo();
    info.Modulation = modName;
    resolvedSymbols = x;

    if isempty(x)
        info.Reason = 'empty input';
        return;
    end
    if ~any(strcmp(modName, {'16APSK','32APSK'}))
        error('HelperTMAPSKASMResolver:UnsupportedModulation', ...
            'Stage-2 resolver supports 16APSK/32APSK only.');
    end

    codeName = lower(strtrim(char(string(localField(options,'ChannelCoding','none')))));
    if ~strcmp(codeName,'none')
        error('HelperTMAPSKASMResolver:UnsupportedCoding', ...
            ['This Stage-2 helper intentionally supports ChannelCoding="none" only. ', ...
             'Do not reuse the uncoded ASM period/template for coded modes.']);
    end

    pcmName = upper(strtrim(char(string(localField(options,'PCMFormat','NRZ-L')))));
    if ~strcmp(pcmName,'NRZ-L')
        error('HelperTMAPSKASMResolver:UnsupportedPCM', ...
            'Stage-2 resolver supports PCMFormat="NRZ-L" only.');
    end

    nBytes = round(localNumber(options,'NumBytesInTransferFrame',1115));
    if ~isfinite(nBytes) || nBytes < 1
        error('HelperTMAPSKASMResolver:InvalidFrameBytes', ...
            'NumBytesInTransferFrame must be a positive integer.');
    end

    asmHex = char(string(localField(options,'ASMHex','1ACFFC1D')));
    asmHex = upper(regexprep(strtrim(asmHex),'^0X',''));
    asmBits = localHexToBits(asmHex);
    asmLen = numel(asmBits);
    if asmLen < 8
        error('HelperTMAPSKASMResolver:InvalidASM', 'ASM must contain at least 8 bits.');
    end

    periodBits = 8*nBytes + asmLen;
    info.ASMHex = asmHex;
    info.ASMLength = asmLen;
    info.PeriodBits = periodBits;

    noiseVar = localNumber(options,'DemodNoiseVariance',0.01);
    noiseVar = max(eps,double(noiseVar));
    maxSearchBits = max(1024,round(localNumber(options,'MaxSearchBits',250000)));
    maxErr = max(0,round(localNumber(options,'ASMMaxErr',6)));
    minGap = localNumber(options,'ASMMinScoreGap',4);
    nTop = max(1,round(localNumber(options,'PeriodicCandidates',32)));
    maxFrames = max(1,round(localNumber(options,'PeriodicFrames',8)));
    errMargin = max(0,round(localNumber(options,'ASMErrMargin',4)));
    allowInversion = localLogical(options,'AllowASMInversion',true);
    requireQualification = localLogical(options,'RequireQualification',true);
    debugEnabled = localLogical(options,'Debug',false);

    % Same four-fold hypothesis set used by the main evaluator for APSK.
    rotations = exp(1j*pi/2*(0:3));
    nRot = numel(rotations);

    scores = -inf(1,nRot);
    bestErrs = inf(1,nRot);
    bestPos = zeros(1,nRot);
    meanErrs = inf(1,nRot);
    nFramesByRot = zeros(1,nRot);
    bestInverted = false(1,nRot);
    hardBitsByRotation = cell(1,nRot);

    for k = 1:nRot
        z = x * rotations(k);
        demodObj = HelperCCSDSTMDemodulator( ...
            'Modulation',modName, ...
            'ChannelCoding','none', ...
            'PCMFormat','NRZ-L', ...
            'NoiseVariance',noiseVar);
        soft = double(demodObj(z));
        hard = int8(real(soft(:)) > 0);
        if numel(hard) > maxSearchBits
            hard = hard(1:maxSearchBits);
        end
        hardBitsByRotation{k} = hard;

        [bestErrs(k),bestPos(k),meanErrs(k),nFramesByRot(k),scores(k),bestInverted(k)] = ...
            localBestASMPeriodicScore(hard,asmBits,periodBits,nTop,maxFrames, ...
                errMargin,allowInversion);
    end

    [sortedScores,order] = sort(scores,'descend');
    if isempty(order) || ~isfinite(sortedScores(1))
        info.Reason = 'no finite ASM rotation score';
        if requireQualification
            return;
        end
        selected = 1;
        gap = -inf;
    else
        selected = order(1);
        if numel(sortedScores) >= 2 && isfinite(sortedScores(2))
            gap = sortedScores(1)-sortedScores(2);
        else
            gap = inf;
        end
    end

    qualified = isfinite(scores(selected)) && ...
        bestErrs(selected) <= maxErr && ...
        gap >= minGap && ...
        nFramesByRot(selected) >= min(2,maxFrames);

    trimBits = 0;
    if bestPos(selected) > 0 && isfinite(periodBits) && periodBits > 0
        % Same bit-phase rule used by localTrimDemodToPeriodicASM in the main
        % evaluator for an uncoded stream (coded ASM offset = 0 here).
        trimBits = mod(bestPos(selected)-1,periodBits);
    end

    resolvedSymbols = x * rotations(selected);

    info.Applied = qualified || ~requireQualification;
    info.Qualified = qualified;
    info.SelectedRotationIndex = selected;
    info.SelectedRotation_deg = localDisplayRotationDeg(rotations(selected));
    info.SelectedRotation = rotations(selected);
    info.Scores = scores;
    info.BestErrors = bestErrs;
    info.BestPositions = bestPos;
    info.MeanErrors = meanErrs;
    info.PeriodicFramesByRotation = nFramesByRot;
    info.ScoreGap = gap;
    info.FirstASMBitPosition = bestPos(selected);
    info.TrimBits = trimBits;
    info.SelectedASMInverted = bestInverted(selected);
    info.MaxAllowedASMError = maxErr;
    info.MinimumScoreGap = minGap;
    info.HardBitsSelected = hardBitsByRotation{selected};

    if qualified
        info.Reason = sprintf(['periodic ASM selected rotation=%+.1f deg, ', ...
            'bestErr=%d, meanErr=%.2f, frames=%d, pos=%d, gap=%.2f, trim=%d'], ...
            info.SelectedRotation_deg,bestErrs(selected),meanErrs(selected), ...
            nFramesByRot(selected),bestPos(selected),gap,trimBits);
    else
        info.Reason = sprintf(['ASM ambiguity not qualified: best rot=%+.1f deg, ', ...
            'bestErr=%.1f/%d, meanErr=%.2f, frames=%d, gap=%.2f/%.2f'], ...
            info.SelectedRotation_deg,bestErrs(selected),maxErr,meanErrs(selected), ...
            nFramesByRot(selected),gap,minGap);
        if requireQualification
            resolvedSymbols = x;
            info.Applied = false;
        end
    end

    if debugEnabled
        fprintf('\n[TM APSK ASM ambiguity resolver]\n');
        fprintf('  modulation       : %s\n',modName);
        fprintf('  coding / PCM     : none / NRZ-L\n');
        fprintf('  ASM              : 0x%s (%d bits)\n',asmHex,asmLen);
        fprintf('  frame period     : %d bits\n',periodBits);
        fprintf('  search bits      : %d\n',min(maxSearchBits,numel(hardBitsByRotation{selected})));
        fprintf('  rotation score table:\n');
        for k = 1:nRot
            fprintf(['    rot=%+6.1f deg score=%8.3f bestErr=%4.0f ', ...
                'mean=%6.2f frames=%2d pos=%7d inv=%d\n'], ...
                localDisplayRotationDeg(rotations(k)),scores(k),bestErrs(k), ...
                meanErrs(k),nFramesByRot(k),bestPos(k),bestInverted(k));
        end
        fprintf('  selected         : %+.1f deg\n',info.SelectedRotation_deg);
        fprintf('  score gap        : %.3f (required >= %.3f)\n',gap,minGap);
        fprintf('  first ASM pos    : %d bits\n',info.FirstASMBitPosition);
        fprintf('  bit trim         : %d bits\n',info.TrimBits);
        fprintf('  ASM inverted     : %d\n',info.SelectedASMInverted);
        fprintf('  qualified        : %d\n',info.Qualified);
        fprintf('  reason           : %s\n',info.Reason);
    end
end

% ========================================================================
% Periodic ASM score: intentionally follows run_ccsds_tm_evaluation logic.
% score = (ASM length - mean periodic error)
%         + 0.75*number of periodic frames
%         - 0.10*single-peak error
% ========================================================================
function [bestErr,bestPos,meanErr,nFrames,score,bestWasInverted] = ...
        localBestASMPeriodicScore(hardBits,asmBits,periodBits,nTop,maxFrames, ...
            errMargin,allowInversion)
    hardBits = int8(hardBits(:) ~= 0);
    asmBits = int8(asmBits(:) ~= 0);
    asmLen = numel(asmBits);

    bestErr = inf;
    bestPos = 0;
    meanErr = inf;
    nFrames = 0;
    score = -inf;
    bestWasInverted = false;

    [errVec,posVec,invVec] = localASMErrorVector(hardBits,asmBits,allowInversion);
    if isempty(errVec)
        return;
    end

    [sortedErr,order] = sort(errVec,'ascend');
    keep = min(nTop,numel(order));
    if isfinite(sortedErr(1))
        keep = min(numel(order),max(keep,nnz(sortedErr <= sortedErr(1)+errMargin)));
    end

    for kk = 1:keep
        idx = order(kk);
        posNow = posVec(idx);
        errNow = sortedErr(kk);
        [meanNow,framesNow] = localPeriodicASMMeanError( ...
            hardBits,asmBits,posNow,periodBits,maxFrames,allowInversion);
        if framesNow <= 0
            meanNow = errNow;
            framesNow = 1;
        end
        scoreNow = (asmLen-meanNow) + 0.75*min(framesNow,maxFrames) - 0.10*errNow;
        if scoreNow > score
            score = scoreNow;
            bestErr = errNow;
            bestPos = posNow;
            meanErr = meanNow;
            nFrames = framesNow;
            bestWasInverted = invVec(idx);
        end
    end
end

function [errVec,posVec,invVec] = localASMErrorVector(hardBits,asmBits,allowInversion)
    hardBits = int8(hardBits(:) ~= 0);
    asmBits = int8(asmBits(:) ~= 0);
    L = numel(asmBits);
    maxStart = numel(hardBits)-L+1;
    if maxStart < 1
        errVec = [];
        posVec = [];
        invVec = [];
        return;
    end

    % Hamming distance from +/-1 correlation; much faster than a MATLAB
    % loop over every bit position while producing the same error count.
    h = 2*double(hardBits)-1;
    a = 2*double(asmBits)-1;
    corr = conv(h,flipud(a),'valid');
    err0 = round((L-corr)/2);

    if allowInversion
        err1 = L-err0;
        invVec = err1 < err0;
        errVec = min(err0,err1);
    else
        invVec = false(size(err0));
        errVec = err0;
    end
    posVec = (1:maxStart).';
end

function [meanErr,nFrames] = localPeriodicASMMeanError( ...
        hardBits,asmBits,firstPos,periodBits,maxFrames,allowInversion)
    hardBits = int8(hardBits(:) ~= 0);
    asmBits = int8(asmBits(:) ~= 0);
    asmInv = int8(~logical(asmBits));
    L = numel(asmBits);
    errs = [];

    pos = firstPos;
    while pos+L-1 <= numel(hardBits) && numel(errs) < maxFrames
        seg = hardBits(pos:pos+L-1);
        e0 = nnz(seg ~= asmBits);
        if allowInversion
            e1 = nnz(seg ~= asmInv);
            e = min(e0,e1);
        else
            e = e0;
        end
        errs(end+1,1) = e; %#ok<AGROW>
        pos = pos+periodBits;
    end

    if isempty(errs)
        meanErr = inf;
        nFrames = 0;
    else
        meanErr = mean(errs);
        nFrames = numel(errs);
    end
end

function bits = localHexToBits(hexText)
    hexText = regexprep(upper(strtrim(char(hexText))),'\s','');
    if isempty(hexText) || any(~ismember(hexText,'0123456789ABCDEF'))
        error('HelperTMAPSKASMResolver:InvalidASMHex','Invalid ASMHex string.');
    end
    bits = zeros(4*numel(hexText),1,'int8');
    p = 1;
    for k = 1:numel(hexText)
        nib = dec2bin(hex2dec(hexText(k)),4)-'0';
        bits(p:p+3) = int8(nib(:));
        p = p+4;
    end
end

function deg = localDisplayRotationDeg(r)
    deg = rad2deg(angle(r));
    if abs(deg+180) < 1e-9
        deg = 180;
    end
end

function info = localEmptyInfo()
    info = struct( ...
        'Applied',false, ...
        'Qualified',false, ...
        'Reason','not run', ...
        'Modulation','', ...
        'ASMHex','', ...
        'ASMLength',0, ...
        'PeriodBits',NaN, ...
        'SelectedRotationIndex',NaN, ...
        'SelectedRotation_deg',NaN, ...
        'SelectedRotation',NaN, ...
        'Scores',[], ...
        'BestErrors',[], ...
        'BestPositions',[], ...
        'MeanErrors',[], ...
        'PeriodicFramesByRotation',[], ...
        'ScoreGap',NaN, ...
        'FirstASMBitPosition',NaN, ...
        'TrimBits',0, ...
        'SelectedASMInverted',false, ...
        'MaxAllowedASMError',NaN, ...
        'MinimumScoreGap',NaN, ...
        'HardBitsSelected',int8([]));
end

function value = localField(s,name,defaultValue)
    if isfield(s,name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = defaultValue;
    end
end

function value = localNumber(s,name,defaultValue)
    raw = localField(s,name,defaultValue);
    if ischar(raw) || isstring(raw)
        value = str2double(string(raw));
    else
        value = double(raw);
    end
end

function value = localLogical(s,name,defaultValue)
    raw = localField(s,name,defaultValue);
    if ischar(raw) || isstring(raw)
        txt = lower(strtrim(char(string(raw))));
        value = any(strcmp(txt,{'1','true','yes','on'}));
    else
        value = logical(raw);
    end
    if ~isscalar(value)
        value = logical(defaultValue);
    end
end
