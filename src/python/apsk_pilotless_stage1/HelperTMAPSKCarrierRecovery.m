function [yOut, state, info] = HelperTMAPSKCarrierRecovery(x, modulation, options)
%HELPERTMAPSKCARRIERRECOVERY Pilotless 16/32APSK carrier recovery.
%
%   [Y, STATE, INFO] = HelperTMAPSKCarrierRecovery(X, MODULATION, OPTIONS)
%
%   Purpose
%   -------
%   Standalone ordinary-TM APSK carrier-recovery helper for laboratory
%   evaluation.  It is intentionally separate from run_ccsds_tm_evaluation
%   so the existing receiver can remain untouched while a pilotless APSK
%   chain is developed and A/B tested.
%
%   Input contract
%   --------------
%   X          : complex, one sample/symbol, AFTER matched filtering and
%                symbol-timing recovery.
%   MODULATION : '16APSK' or '32APSK'.
%   OPTIONS    : struct.  Important fields are listed below.
%
%   Algorithm
%   ---------
%   1) Unit-average-power normalization.
%   2) Pilotless feed-forward acquisition:
%      - split an acquisition prefix into short blocks;
%      - for each block, search the APSK four-fold phase fundamental region;
%      - metric = trimmed nearest-constellation squared distance;
%      - unwrap 4*phase and fit a straight phase trajectory;
%      - the fitted slope provides a residual CFO estimate.
%   3) Decision-directed second-order PLL:
%      - nearest APSK symbol phase detector;
%      - nearest/second-nearest reliability margin;
%      - unreliable symbols NEVER update frequency/phase-loop error state;
%      - optional power-fade HOLD with hysteresis;
%      - during HOLD the NCO continues with the last reliable frequency
%        estimate (holdover), but decision errors are not integrated.
%
%   IMPORTANT
%   ---------
%   This implementation follows the practical architecture suggested by the
%   APSK NDA/DD carrier-recovery literature, but it is NOT a verbatim
%   implementation of any single Gappmair et al. detector equation.  The NDA
%   acquisition here is a constellation-likelihood/grid metric chosen because
%   it is easy to audit against this project's exact CCSDS constellation.
%
%   Four-fold ambiguity
%   -------------------
%   16/32APSK have pi/2 rotational symmetry.  This helper intentionally does
%   not use transmitted bits or pilots to resolve the remaining 0/90/180/270
%   degree ambiguity.  Resolve it later with the CCSDS ASM/frame marker (or,
%   only in a laboratory diagnostic, by trying four rotations against TX
%   truth).
%
%   Default OPTIONS
%   ---------------
%   SymbolRateHz                    = 10e6
%   ReferenceConstellation          = []   % use project CCSDS helper
%   NormalizeInputPower             = true
%
%   AcquisitionSymbols             = 4096
%   AcquisitionBlockSymbols        = 16
%   AcquisitionPhaseGridSize       = 181
%   AcquisitionTrimFraction        = 0.10
%   AcquisitionMetricMax           = NaN  % auto from min distance
%   MaxAcquisitionCFOHz             = 0.02*SymbolRateHz
%   RequireAcquisitionQualification = true
%
%   DDLoopBandwidth                = 0.002
%   DampingFactor                  = 1/sqrt(2)
%   DecisionGate                   = NaN   % auto = 0.40*dmin
%   DecisionMarginMin              = 0.12
%   MaxPhaseErrorRad               = pi/5
%   MaxResidualCFOHz               = 0.01*SymbolRateHz
%
%   HoldEnterBadSymbols            = 4
%   RecoverGoodSymbols             = 8
%   EnableFadeHold                 = true
%   FadePowerTauSymbols            = 64
%   FadeEnterDB                    = -10
%   FadeExitDB                     = -6
%
%   Debug                          = false
%
%   STATE contains the final NCO and mode state.  INFO contains acquisition,
%   decision-gate, hold and residual-quality diagnostics.
%
%   See also HelperTMBlindCMAEqualizer, HelperCCSDSFACMReferenceConstellation.

    if nargin < 2 || isempty(modulation)
        modulation = '32APSK';
    end
    if nargin < 3 || isempty(options)
        options = struct();
    end

    x = complex(x(:));
    modulation = upper(strtrim(string(modulation)));

    if ~any(modulation == ["16APSK","32APSK"])
        error('HelperTMAPSKCarrierRecovery:UnsupportedModulation', ...
            'MODULATION must be 16APSK or 32APSK.');
    end

    info = localEmptyInfo();
    info.Modulation = char(modulation);

    if isempty(x)
        yOut = x;
        state = localEmptyState();
        info.Reason = 'empty input';
        return;
    end
    if any(~isfinite(real(x))) || any(~isfinite(imag(x)))
        error('HelperTMAPSKCarrierRecovery:NonfiniteInput', ...
            'Input contains NaN or Inf.');
    end

    Rs = localNumber(options,'SymbolRateHz',10e6);
    if ~isscalar(Rs) || ~isfinite(Rs) || Rs <= 0
        error('HelperTMAPSKCarrierRecovery:InvalidSymbolRate', ...
            'SymbolRateHz must be a finite positive scalar.');
    end

    refConst = localReferenceConstellation(modulation, options);
    refConst = complex(refConst(:));
    if isempty(refConst) || any(~isfinite(refConst))
        error('HelperTMAPSKCarrierRecovery:InvalidReference', ...
            'Reference constellation is empty or invalid.');
    end
    refConst = refConst / sqrt(mean(abs(refConst).^2) + eps);

    refPower = mean(abs(refConst).^2);
    minDistance = localMinimumDistance(refConst);
    if ~isfinite(minDistance) || minDistance <= 0
        error('HelperTMAPSKCarrierRecovery:InvalidReferenceDistance', ...
            'Reference constellation has zero minimum distance.');
    end

    normalizeInput = localLogical(options,'NormalizeInputPower',true);
    inputPower = mean(abs(x).^2) + eps;
    if normalizeInput
        xNorm = x * sqrt(refPower/inputPower);
    else
        xNorm = x;
    end

    % ---------- Options: acquisition ----------
    acqSymbols = max(32, round(localNumber(options,'AcquisitionSymbols',4096)));
    acqSymbols = min(acqSymbols, numel(xNorm));
    blockSymbols = max(4, round(localNumber(options,'AcquisitionBlockSymbols',16)));
    blockSymbols = min(blockSymbols, acqSymbols);
    phaseGridSize = max(31, round(localNumber(options,'AcquisitionPhaseGridSize',181)));
    trimFraction = localNumber(options,'AcquisitionTrimFraction',0.10);
    trimFraction = min(max(trimFraction,0),0.45);
    maxAcqCFOHz = localNumber(options,'MaxAcquisitionCFOHz',0.02*Rs);
    maxAcqCFOHz = max(0, double(maxAcqCFOHz));
    requireAcq = localLogical(options,'RequireAcquisitionQualification',true);

    acqMetricMax = localNumber(options,'AcquisitionMetricMax',NaN);
    if ~isfinite(acqMetricMax) || acqMetricMax <= 0
        acqMetricMax = (0.45*minDistance)^2;
    end

    % ---------- Options: DD PLL ----------
    loopBW = localNumber(options,'DDLoopBandwidth',0.002);
    damping = localNumber(options,'DampingFactor',1/sqrt(2));
    if ~isscalar(loopBW) || ~isfinite(loopBW) || loopBW <= 0 || loopBW > 0.2
        error('HelperTMAPSKCarrierRecovery:InvalidLoopBandwidth', ...
            'DDLoopBandwidth must be in (0,0.2].');
    end
    if ~isscalar(damping) || ~isfinite(damping) || damping <= 0
        error('HelperTMAPSKCarrierRecovery:InvalidDamping', ...
            'DampingFactor must be positive.');
    end
    [alpha,beta] = localSecondOrderLoopGains(loopBW,damping);

    decisionGate = localNumber(options,'DecisionGate',NaN);
    if ~isfinite(decisionGate) || decisionGate <= 0
        decisionGate = 0.40*minDistance;
    end
    decisionMarginMin = localNumber(options,'DecisionMarginMin',0.12);
    decisionMarginMin = min(max(decisionMarginMin,0),0.95);
    maxPhaseError = localNumber(options,'MaxPhaseErrorRad',pi/5);
    maxPhaseError = min(max(maxPhaseError,deg2rad(2)),pi/2);
    maxResidualCFOHz = localNumber(options,'MaxResidualCFOHz',0.01*Rs);
    maxResidualOmega = 2*pi*max(0,maxResidualCFOHz)/Rs;

    holdEnterBad = max(1,round(localNumber(options,'HoldEnterBadSymbols',4)));
    recoverGood = max(1,round(localNumber(options,'RecoverGoodSymbols',8)));

    enableFadeHold = localLogical(options,'EnableFadeHold',true);
    fadeTau = max(4,localNumber(options,'FadePowerTauSymbols',64));
    fadeEnterDB = localNumber(options,'FadeEnterDB',-10);
    fadeExitDB = localNumber(options,'FadeExitDB',-6);
    if fadeExitDB <= fadeEnterDB
        error('HelperTMAPSKCarrierRecovery:InvalidFadeHysteresis', ...
            'FadeExitDB must be greater than FadeEnterDB.');
    end
    fadeEnterRatio = 10^(fadeEnterDB/10);
    fadeExitRatio = 10^(fadeExitDB/10);
    fadeAlpha = 1 - exp(-1/fadeTau);

    debugEnabled = localLogical(options,'Debug',false);

    % ================================================================
    % 1) Pilotless feed-forward acquisition
    % ================================================================
    [acq, acqOk] = localNDAAcquisition( ...
        xNorm(1:acqSymbols), refConst, Rs, blockSymbols, ...
        phaseGridSize, trimFraction, acqMetricMax, maxAcqCFOHz);

    info.AcquisitionSymbols = acqSymbols;
    info.AcquisitionBlockSymbols = blockSymbols;
    info.AcquisitionBlocks = numel(acq.BlockPhaseRad);
    info.AcquisitionPhaseGridSize = phaseGridSize;
    info.AcquisitionTrimFraction = trimFraction;
    info.AcquisitionMedianMetric = acq.MedianMetric;
    info.AcquisitionMetricMax = acqMetricMax;
    info.AcquisitionQualified = acqOk;
    info.AcquisitionPhase_deg = rad2deg(localWrapPi(acq.PhaseInterceptRad));
    info.AcquisitionCFO_Hz = acq.CFOHz;
    info.AcquisitionBlockPhase_deg = rad2deg(acq.BlockPhaseRad(:));
    info.AcquisitionBlockPhaseUnwrapped_deg = rad2deg(acq.BlockPhaseUnwrappedRad(:));
    info.AcquisitionBlockMetric = acq.BlockMetric(:);
    info.AcquisitionBlockCenter = acq.BlockCenter(:);

    if requireAcq && ~acqOk
        yOut = xNorm;
        state = localEmptyState();
        state.Mode = 'ACQUIRE_FAILED';
        info.Applied = false;
        info.Reason = sprintf(['NDA acquisition not qualified: medianMetric=%.4g ', ...
            '(limit %.4g), CFO=%+.3f Hz'], ...
            acq.MedianMetric, acqMetricMax, acq.CFOHz);
        if debugEnabled
            localPrintInfo(info, NaN, NaN, 0, 0, 0);
        end
        return;
    end

    n0 = (0:numel(xNorm)-1).';
    acquisitionPhase = acq.PhaseInterceptRad + acq.OmegaRadPerSymbol*n0;
    xFF = xNorm .* exp(-1j*acquisitionPhase);

    % ================================================================
    % 2) Gated decision-directed PLL + HOLD/RECOVER
    % ================================================================
    yOut = complex(zeros(size(xFF)));
    accepted = false(size(xFF));
    fadeMask = false(size(xFF));
    holdMask = false(size(xFF));
    phaseErrorVec = NaN(size(xFF));
    decisionDistance = NaN(size(xFF));
    decisionMargin = NaN(size(xFF));

    phaseState = 0;
    freqState = 0;
    mode = "TRACK";
    badCount = 0;
    goodCount = 0;
    holdEvents = 0;
    recoverEvents = 0;

    % The IIR power detector sees many APSK ring amplitudes, so it must be
    % deliberately slow.  Initialize it from the first short segment rather
    % than one symbol to avoid a first-ring bias.
    pInitLen = min(max(16,round(fadeTau/2)),numel(xFF));
    powerIIR = mean(abs(xFF(1:pInitLen)).^2) + eps;
    powerReference = refPower;
    inPowerFade = false;

    for n = 1:numel(xFF)
        % Phase output uses the current NCO state.
        z = xFF(n) * exp(-1j*phaseState);
        yOut(n) = z;

        [dHat,d1,d2] = localNearestTwo(z,refConst);
        margin = max(0,(d2-d1)/(d2+eps));
        phErr = angle(z*conj(dHat));

        decisionDistance(n) = d1;
        decisionMargin(n) = margin;
        phaseErrorVec(n) = phErr;

        % Slow, decision-free local power observation.
        powerIIR = (1-fadeAlpha)*powerIIR + fadeAlpha*abs(xFF(n))^2;
        powerRatio = powerIIR/(powerReference+eps);

        if enableFadeHold
            if ~inPowerFade && powerRatio < fadeEnterRatio
                inPowerFade = true;
            elseif inPowerFade && powerRatio > fadeExitRatio
                inPowerFade = false;
            end
        else
            inPowerFade = false;
        end
        fadeMask(n) = inPowerFade;

        reliableDecision = d1 <= decisionGate && ...
            margin >= decisionMarginMin && ...
            abs(phErr) <= maxPhaseError && ...
            ~inPowerFade;

        switch mode
            case "TRACK"
                if reliableDecision
                    accepted(n) = true;
                    badCount = 0;
                    goodCount = min(goodCount+1,recoverGood);

                    freqState = freqState + beta*phErr;
                    freqState = min(max(freqState,-maxResidualOmega),maxResidualOmega);
                    phaseState = phaseState + freqState + alpha*phErr;
                else
                    % Never integrate a dubious decision.  Continue NCO
                    % prediction with the last reliable frequency estimate.
                    badCount = badCount + 1;
                    goodCount = 0;
                    phaseState = phaseState + freqState;
                    if badCount >= holdEnterBad || inPowerFade
                        mode = "HOLD";
                        holdEvents = holdEvents + 1;
                    end
                end

            case "HOLD"
                holdMask(n) = true;
                % Holdover: only the old frequency estimate propagates.
                phaseState = phaseState + freqState;
                badCount = 0;

                if reliableDecision
                    goodCount = goodCount + 1;
                else
                    goodCount = 0;
                end

                if goodCount >= recoverGood
                    mode = "TRACK";
                    recoverEvents = recoverEvents + 1;
                    goodCount = 0;
                end

            otherwise
                mode = "TRACK";
                phaseState = phaseState + freqState;
        end

        phaseState = localWrapPi(phaseState);
    end

    validPhaseErr = phaseErrorVec(accepted & isfinite(phaseErrorVec));
    if isempty(validPhaseErr)
        phaseErrRMS = NaN;
        meanAbsPhaseErr = NaN;
    else
        phaseErrRMS = sqrt(mean(validPhaseErr.^2));
        meanAbsPhaseErr = mean(abs(validPhaseErr));
    end

    validDist = decisionDistance(isfinite(decisionDistance));
    if isempty(validDist)
        meanDist = NaN;
    else
        meanDist = mean(validDist);
    end

    info.Applied = true;
    info.Reason = 'NDA feed-forward acquisition + gated DD second-order PLL';
    info.AmbiguityOrder = 4;
    info.AmbiguityPeriod_deg = 90;
    info.InputPower = inputPower;
    info.NormalizedInputPower = mean(abs(xNorm).^2);
    info.ReferenceMinimumDistance = minDistance;
    info.DecisionGate = decisionGate;
    info.DecisionMarginMin = decisionMarginMin;
    info.DDLoopBandwidth = loopBW;
    info.DampingFactor = damping;
    info.LoopAlpha = alpha;
    info.LoopBeta = beta;
    info.AcceptedDecisions = nnz(accepted);
    info.AcceptanceRate = mean(accepted);
    info.HoldSymbols = nnz(holdMask);
    info.HoldFraction = mean(holdMask);
    info.HoldEvents = holdEvents;
    info.RecoverEvents = recoverEvents;
    info.FadeSymbols = nnz(fadeMask);
    info.FadeFraction = mean(fadeMask);
    info.PhaseErrorRMS_deg = rad2deg(phaseErrRMS);
    info.MeanAbsPhaseError_deg = rad2deg(meanAbsPhaseErr);
    info.MeanDecisionDistance = meanDist;
    info.FinalResidualFrequency_Hz = freqState*Rs/(2*pi);
    info.FinalResidualPhase_deg = rad2deg(phaseState);

    state = struct();
    state.Mode = char(mode);
    state.PhaseRad = phaseState;
    state.FrequencyRadPerSymbol = freqState;
    state.FrequencyHz = freqState*Rs/(2*pi);
    state.BadCounter = badCount;
    state.GoodCounter = goodCount;
    state.PowerIIR = powerIIR;
    state.PowerFade = inPowerFade;
    state.AcquisitionPhaseInterceptRad = acq.PhaseInterceptRad;
    state.AcquisitionOmegaRadPerSymbol = acq.OmegaRadPerSymbol;
    state.AcquisitionCFOHz = acq.CFOHz;

    if debugEnabled
        localPrintInfo(info, decisionGate, minDistance, ...
            nnz(accepted), nnz(holdMask), nnz(fadeMask));
    end
end

% ========================================================================
% Local helpers
% ========================================================================
function refConst = localReferenceConstellation(modulation, options)
    if isfield(options,'ReferenceConstellation') && ...
            ~isempty(options.ReferenceConstellation)
        refConst = complex(options.ReferenceConstellation(:));
        return;
    end

    switch upper(string(modulation))
        case "16APSK"
            refConst = HelperCCSDSFACMReferenceConstellation(14);
        case "32APSK"
            refConst = HelperCCSDSFACMReferenceConstellation(21);
        otherwise
            refConst = [];
    end
end

function [acq, qualified] = localNDAAcquisition(x, refConst, Rs, ...
        blockSymbols, phaseGridSize, trimFraction, metricMax, maxCFOHz)

    x = complex(x(:));
    N = numel(x);
    nBlocks = floor(N/blockSymbols);

    acq = struct( ...
        'BlockPhaseRad',zeros(0,1), ...
        'BlockPhaseUnwrappedRad',zeros(0,1), ...
        'BlockMetric',zeros(0,1), ...
        'BlockCenter',zeros(0,1), ...
        'MedianMetric',inf, ...
        'PhaseInterceptRad',0, ...
        'OmegaRadPerSymbol',0, ...
        'CFOHz',0);

    if nBlocks < 3
        qualified = false;
        return;
    end

    % Four-fold APSK symmetry: search one fundamental pi/2 interval.
    phaseGrid = linspace(-pi/4,pi/4,phaseGridSize+1);
    phaseGrid(end) = [];

    blockPhase = zeros(nBlocks,1);
    blockMetric = inf(nBlocks,1);
    blockCenter = zeros(nBlocks,1);
    refPower = mean(abs(refConst).^2);

    for b = 1:nBlocks
        i1 = (b-1)*blockSymbols + 1;
        i2 = b*blockSymbols;
        xb = x(i1:i2);

        % Remove only a COMMON block scale.  Ring ratios remain intact.
        pb = mean(abs(xb).^2) + eps;
        xb = xb*sqrt(refPower/pb);

        bestMetric = inf;
        bestPhase = 0;
        for k = 1:numel(phaseGrid)
            phi = phaseGrid(k);
            z = xb*exp(-1j*phi);
            d2 = min(abs(z-refConst.').^2,[],2);
            m = localTrimmedMean(d2,trimFraction);
            if m < bestMetric
                bestMetric = m;
                bestPhase = phi;
            end
        end
        blockPhase(b) = bestPhase;
        blockMetric(b) = bestMetric;
        blockCenter(b) = ((i1+i2)/2)-1; % zero-based symbol index
    end

    % Because phase estimates live modulo pi/2, unwrap in fourfold space.
    phaseUnwrapped = unwrap(4*blockPhase)/4;

    medianMetric = median(blockMetric(isfinite(blockMetric)));
    if isempty(medianMetric) || ~isfinite(medianMetric)
        medianMetric = inf;
    end

    % Reject only obvious metric outliers for the trajectory fit.
    good = isfinite(blockMetric) & isfinite(phaseUnwrapped);
    if isfinite(medianMetric) && medianMetric > 0
        good = good & blockMetric <= max(4*medianMetric,metricMax*2);
    end
    if nnz(good) < 3
        good = isfinite(blockMetric) & isfinite(phaseUnwrapped);
    end

    t = blockCenter(good);
    p = phaseUnwrapped(good);
    m = blockMetric(good);

    if numel(t) < 3
        qualified = false;
        acq.BlockPhaseRad = blockPhase;
        acq.BlockPhaseUnwrappedRad = phaseUnwrapped;
        acq.BlockMetric = blockMetric;
        acq.BlockCenter = blockCenter;
        acq.MedianMetric = medianMetric;
        return;
    end

    % Metric-weighted least squares.  Cap the weight ratio so one block
    % cannot dominate the entire CFO estimate.
    metricFloor = max(eps,0.05*max(medianMetric,eps));
    w = 1./max(m,metricFloor);
    wMed = median(w);
    if isfinite(wMed) && wMed > 0
        w = min(w,10*wMed);
    end
    A = [ones(numel(t),1), t(:)];
    sw = sqrt(w(:));
    Aw = A.*sw;
    pw = p(:).*sw;
    coeff = Aw\pw;

    phase0 = coeff(1);
    omega = coeff(2);
    cfoHz = omega*Rs/(2*pi);

    acq.BlockPhaseRad = blockPhase;
    acq.BlockPhaseUnwrappedRad = phaseUnwrapped;
    acq.BlockMetric = blockMetric;
    acq.BlockCenter = blockCenter;
    acq.MedianMetric = medianMetric;
    acq.PhaseInterceptRad = phase0;
    acq.OmegaRadPerSymbol = omega;
    acq.CFOHz = cfoHz;

    qualified = isfinite(phase0) && isfinite(omega) && ...
        isfinite(medianMetric) && medianMetric <= metricMax && ...
        abs(cfoHz) <= maxCFOHz;
end

function m = localTrimmedMean(x,trimFraction)
    x = sort(real(x(isfinite(x))),'ascend');
    if isempty(x)
        m = inf;
        return;
    end
    keep = max(1,floor((1-trimFraction)*numel(x)));
    m = mean(x(1:keep));
end

function [dHat,d1,d2] = localNearestTwo(z,refConst)
    dist = abs(z-refConst);
    [s,idx] = sort(dist,'ascend');
    dHat = refConst(idx(1));
    d1 = s(1);
    if numel(s) >= 2
        d2 = s(2);
    else
        d2 = inf;
    end
end

function dmin = localMinimumDistance(refConst)
    refConst = refConst(:);
    dmin = inf;
    for k = 1:numel(refConst)
        d = abs(refConst(k)-refConst);
        d(k) = inf;
        dmin = min(dmin,min(d));
    end
end

function [alpha,beta] = localSecondOrderLoopGains(Bn,zeta)
    % Standard normalized second-order digital PLL coefficient mapping.
    theta = Bn/(zeta + 1/(4*zeta));
    den = 1 + 2*zeta*theta + theta^2;
    alpha = (4*zeta*theta)/den;
    beta = (4*theta^2)/den;
end

function y = localWrapPi(x)
    y = mod(x+pi,2*pi)-pi;
end

function value = localNumber(s,name,defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        raw = s.(name);
        if isnumeric(raw) || islogical(raw)
            value = double(raw);
        else
            value = str2double(string(raw));
        end
    end
end

function value = localLogical(s,name,defaultValue)
    value = logical(defaultValue);
    if ~(isstruct(s) && isfield(s,name) && ~isempty(s.(name)))
        return;
    end
    raw = s.(name);
    if islogical(raw) || isnumeric(raw)
        value = logical(raw(1));
        return;
    end
    text = lower(strtrim(string(raw)));
    value = any(text == ["true","1","yes","on"]);
end

function state = localEmptyState()
    state = struct( ...
        'Mode','UNINITIALIZED', ...
        'PhaseRad',0, ...
        'FrequencyRadPerSymbol',0, ...
        'FrequencyHz',0, ...
        'BadCounter',0, ...
        'GoodCounter',0, ...
        'PowerIIR',NaN, ...
        'PowerFade',false, ...
        'AcquisitionPhaseInterceptRad',0, ...
        'AcquisitionOmegaRadPerSymbol',0, ...
        'AcquisitionCFOHz',0);
end

function info = localEmptyInfo()
    info = struct( ...
        'Applied',false, ...
        'Reason','', ...
        'Modulation','', ...
        'AmbiguityOrder',4, ...
        'AmbiguityPeriod_deg',90, ...
        'InputPower',NaN, ...
        'NormalizedInputPower',NaN, ...
        'ReferenceMinimumDistance',NaN, ...
        'AcquisitionSymbols',0, ...
        'AcquisitionBlockSymbols',0, ...
        'AcquisitionBlocks',0, ...
        'AcquisitionPhaseGridSize',0, ...
        'AcquisitionTrimFraction',NaN, ...
        'AcquisitionMedianMetric',NaN, ...
        'AcquisitionMetricMax',NaN, ...
        'AcquisitionQualified',false, ...
        'AcquisitionPhase_deg',NaN, ...
        'AcquisitionCFO_Hz',NaN, ...
        'AcquisitionBlockPhase_deg',zeros(0,1), ...
        'AcquisitionBlockPhaseUnwrapped_deg',zeros(0,1), ...
        'AcquisitionBlockMetric',zeros(0,1), ...
        'AcquisitionBlockCenter',zeros(0,1), ...
        'DecisionGate',NaN, ...
        'DecisionMarginMin',NaN, ...
        'DDLoopBandwidth',NaN, ...
        'DampingFactor',NaN, ...
        'LoopAlpha',NaN, ...
        'LoopBeta',NaN, ...
        'AcceptedDecisions',0, ...
        'AcceptanceRate',0, ...
        'HoldSymbols',0, ...
        'HoldFraction',0, ...
        'HoldEvents',0, ...
        'RecoverEvents',0, ...
        'FadeSymbols',0, ...
        'FadeFraction',0, ...
        'PhaseErrorRMS_deg',NaN, ...
        'MeanAbsPhaseError_deg',NaN, ...
        'MeanDecisionDistance',NaN, ...
        'FinalResidualFrequency_Hz',NaN, ...
        'FinalResidualPhase_deg',NaN);
end

function localPrintInfo(info,decisionGate,minDistance,nAccepted,nHold,nFade)
    fprintf('\n[TM APSK pilotless carrier recovery]\n');
    fprintf('  modulation      : %s\n',info.Modulation);
    fprintf('  NDA qualified   : %d\n',info.AcquisitionQualified);
    fprintf('  NDA CFO         : %+.3f Hz\n',info.AcquisitionCFO_Hz);
    fprintf('  NDA phase       : %+.3f deg (mod 90 deg)\n',info.AcquisitionPhase_deg);
    fprintf('  NDA metric      : %.5g / %.5g\n', ...
        info.AcquisitionMedianMetric,info.AcquisitionMetricMax);
    if isfinite(decisionGate)
        fprintf('  DD gate         : %.5g (dmin %.5g), margin>=%.3f\n', ...
            decisionGate,minDistance,info.DecisionMarginMin);
    end
    fprintf('  DD accept       : %d / %d = %.2f%%\n', ...
        nAccepted,max(1,nAccepted+nHold),100*info.AcceptanceRate);
    fprintf('  HOLD/fade       : %d / %d symbols, events=%d recoveries=%d\n', ...
        nHold,nFade,info.HoldEvents,info.RecoverEvents);
    fprintf('  phase error RMS : %.3f deg\n',info.PhaseErrorRMS_deg);
    fprintf('  final DD freq   : %+.3f Hz\n',info.FinalResidualFrequency_Hz);
    fprintf('  ambiguity       : unresolved modulo %g deg; use ASM later\n\n', ...
        info.AmbiguityPeriod_deg);
end
