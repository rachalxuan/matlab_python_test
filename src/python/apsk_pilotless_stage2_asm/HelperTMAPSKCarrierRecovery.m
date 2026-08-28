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
%      - Mth-power FFT coarse-CFO acquisition (M=12/48 by default);
%      - split an acquisition prefix into short blocks;
%      - for each block, search the APSK four-fold phase fundamental region;
%      - metric = trimmed nearest-constellation squared distance;
%      - unwrap 4*phase and fit the remaining phase trajectory;
%      - combine FFT coarse CFO and NDA residual CFO.
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
%   AcquisitionRangeToleranceHz     = NaN  % auto from coarse FFT bin
%   RequireAcquisitionQualification = true
%   EnableFourthPowerFFTCoarseCFO   = true
%   FourthPowerFFTLength            = 65536
%   FourthPowerMinConfidenceDB      = 6
%   RequireFourthPowerQualification = true
%   UseGlobalNDAPhase               = true
%   ApplyNDAResidualCFO             = false
%   EnableWideRangeRingCoarseCFO   = false
%   CoarsePowerOrder                = 12 (wide mode), 48 (legacy 32APSK)
%   CoarseUseInnerMiddleRings       = true for 32APSK
%   EnablePreDDGainTracker          = false
%   PreDDGainTracker                = struct()
%
%   DDLoopBandwidth                = 0.002
%   DampingFactor                  = 1/sqrt(2)
%   DecisionGate                   = NaN   % auto = 0.40*dmin
%   DecisionMarginMin              = 0.12
%   MaxPhaseErrorRad               = pi/5
%   MaxResidualCFOHz               = 0.01*SymbolRateHz
%   UseCommonSecondOrderLoop        = false
%   DDAcquireLoopBandwidth          = max(0.01,DDLoopBandwidth)
%   DDIgnoreInnerRing               = false
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
    debugEnabled = localLogical(options,'Debug',false);

    enableFourthPower = localLogical(options, ...
        'EnableFourthPowerFFTCoarseCFO',true);
    requireFourthPower = localLogical(options, ...
        'RequireFourthPowerQualification',true);
    useGlobalNDAPhase = localLogical(options,'UseGlobalNDAPhase',true);
    applyNDAResidualCFO = localLogical(options, ...
        'ApplyNDAResidualCFO',false);
    fourthPowerInfo = localEmptyFourthPowerInfo();
    coarseCFOHz = 0;
    % A single x^48 operation removes every 32APSK data phase, but its CFO
    % estimate is periodic every Rs/48 and therefore aliases outside about
    % +/-Rs/96. For 50 Msym/s that is only +/-0.52 MHz.  Ring partitioning
    % lets the inner+middle (4/12-point) subset use x^12, extending the
    % unambiguous range to about +/-Rs/24 while keeping a clean spectral
    % line. 16APSK already has only 4/12-point rings and also uses x^12.
    % Preserve the historical 32APSK x^48 acquisition unless the isolated
    % wide-range experiment is explicitly enabled. This keeps the main
    % receiver default unchanged and makes the new path easy to A/B test.
    enableWideRangeCoarse = modulation == "32APSK" && ...
        localLogical(options,'EnableWideRangeRingCoarseCFO',false);
    if modulation == "32APSK" && ~enableWideRangeCoarse
        defaultPowerOrder = 48;
    else
        defaultPowerOrder = 12;
    end
    coarsePowerOrder = max(1,round(localNumber(options, ...
        'CoarsePowerOrder',defaultPowerOrder)));
    if enableFourthPower
        fftOpt = struct( ...
            'AcquisitionSymbols',acqSymbols, ...
            'FFTLength',localNumber(options,'FourthPowerFFTLength',65536), ...
            'MaxCFOHz',maxAcqCFOHz, ...
            'PowerOrder',coarsePowerOrder, ...
            'MinConfidenceDB',localNumber(options, ...
                'FourthPowerMinConfidenceDB',6), ...
            'UseUnitMagnitude',localLogical(options, ...
                'FourthPowerUseUnitMagnitude',true));
        useInnerMiddleRings = enableWideRangeCoarse && ...
            localLogical(options,'CoarseUseInnerMiddleRings',true) && ...
            coarsePowerOrder == 12;
        if useInnerMiddleRings
            ringRadii = localUniqueRadii(refConst);
            if numel(ringRadii) >= 3
                fftOpt.RadiusMax = 0.5*(ringRadii(2)+ringRadii(3));
            end
        end
        explicitRadiusMax = localNumber(options,'CoarseRadiusMax',NaN);
        if isfinite(explicitRadiusMax) && explicitRadiusMax > 0
            fftOpt.RadiusMax = explicitRadiusMax;
        end
        fftOpt.MinSelectedSymbols = max(8,round(localNumber(options, ...
            'CoarseMinSelectedSymbols',64)));
        fftOpt.RangeToleranceHz = localNumber(options, ...
            'CoarseRangeToleranceHz',NaN);
        [coarseCFOHz,fourthPowerInfo] = ...
            HelperTMAPSKFourthPowerCoarseCFO( ...
                xNorm(1:acqSymbols),Rs,fftOpt);
        if requireFourthPower && ~fourthPowerInfo.Qualified
            yOut = xNorm;
            state = localEmptyState();
            state.Mode = 'ACQUIRE_FAILED';
            info.Applied = false;
            info.AcquisitionQualified = false;
            info.FourthPowerQualified = false;
            info.CoarsePowerOrder = coarsePowerOrder;
            info.FourthPowerCFO_Hz = coarseCFOHz;
            info.FourthPowerConfidence_dB = fourthPowerInfo.ConfidenceDB;
            info.Reason = sprintf([ ...
                'fourth-power coarse CFO not qualified: CFO=%+.3f Hz, ', ...
                'confidence=%.2f dB'], ...
                coarseCFOHz,fourthPowerInfo.ConfidenceDB);
            if debugEnabled
                localPrintInfo(info,NaN,NaN,0,0,0);
            end
            return;
        end
    end

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
    enableDDPhaseTracker = localLogical(options,'EnableDDPhaseTracker',true);
    ddResidualPhaseLimit = localNumber(options, ...
        'DDResidualPhaseLimitRad',NaN);
    if ~isfinite(ddResidualPhaseLimit) || ddResidualPhaseLimit <= 0
        ddResidualPhaseLimit = inf;
    else
        ddResidualPhaseLimit = min(ddResidualPhaseLimit,pi/2);
    end
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

    acquisitionRangeToleranceHz = localNumber(options, ...
        'AcquisitionRangeToleranceHz',NaN);
    if ~isfinite(acquisitionRangeToleranceHz) || ...
            acquisitionRangeToleranceHz < 0
        acquisitionRangeToleranceHz = localInfoNumber( ...
            fourthPowerInfo,'RangeToleranceHz',0);
    end

    % ================================================================
    % 1) Pilotless feed-forward acquisition
    % ================================================================
    [acq, acqOk] = localNDAAcquisition( ...
        xNorm(1:acqSymbols), refConst, Rs, blockSymbols, ...
        phaseGridSize, trimFraction, acqMetricMax, ...
        maxAcqCFOHz+acquisitionRangeToleranceHz, ...
        coarseCFOHz,useGlobalNDAPhase,applyNDAResidualCFO);

    info.AcquisitionSymbols = acqSymbols;
    info.AcquisitionBlockSymbols = blockSymbols;
    info.AcquisitionBlocks = numel(acq.BlockPhaseRad);
    info.AcquisitionPhaseGridSize = phaseGridSize;
    info.AcquisitionTrimFraction = trimFraction;
    info.AcquisitionMedianMetric = acq.MedianMetric;
    info.AcquisitionMetricMax = acqMetricMax;
    info.AcquisitionRangeTolerance_Hz = acquisitionRangeToleranceHz;
    info.AcquisitionQualified = acqOk;
    info.AcquisitionPhase_deg = rad2deg(localWrapPi(acq.PhaseInterceptRad));
    info.AcquisitionCFO_Hz = acq.CFOHz;
    info.FourthPowerEnabled = enableFourthPower;
    info.FourthPowerQualified = fourthPowerInfo.Qualified;
    info.WideRangeRingCoarseEnabled = enableWideRangeCoarse;
    info.CoarsePowerOrder = coarsePowerOrder;
    info.FourthPowerCFO_Hz = coarseCFOHz;
    info.FourthPowerConfidence_dB = fourthPowerInfo.ConfidenceDB;
    info.CoarseSelectedSymbols = localInfoNumber(fourthPowerInfo, ...
        'SelectedSymbols',NaN);
    info.CoarseSelectionFraction = localInfoNumber(fourthPowerInfo, ...
        'SelectionFraction',NaN);
    info.CoarseRadiusMax = localInfoNumber(fourthPowerInfo, ...
        'RadiusMax',NaN);
    info.CoarseUnambiguousMaxCFO_Hz = localInfoNumber( ...
        fourthPowerInfo,'UnambiguousMaxCFOHz',NaN);
    info.NDAResidualCFO_Hz = acq.ResidualCFOHz;
    info.NDAResidualCFOApplied = acq.ResidualCFOApplied;
    info.GlobalNDAPhaseUsed = acq.GlobalPhaseUsed;
    info.GlobalNDAPhase_deg = rad2deg(acq.GlobalPhaseRad);
    info.GlobalNDAMetric = acq.GlobalMetric;
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
    % 2) NDA Mth-power time-varying phase tracking
    % ================================================================
    enableMthPhaseTracker = localLogical(options, ...
        'EnableMthPowerPhaseTracker',false);
    mthPhaseState = struct();
    mthPhaseInfo = localEmptyMthPhaseInfo();
    xPhaseTracked = xFF;
    if enableMthPhaseTracker
        mthOpt = struct();
        if isfield(options,'MthPowerPhaseTracker') && ...
                isstruct(options.MthPowerPhaseTracker)
            mthOpt = options.MthPowerPhaseTracker;
        end
        if ~isfield(mthOpt,'Debug')
            mthOpt.Debug = debugEnabled;
        end
        [xPhaseTracked,mthPhaseState,mthPhaseInfo] = ...
            HelperTMAPSKMthPowerPhaseTracker( ...
            xFF,coarsePowerOrder,mthOpt);
    end

    % ================================================================
    % 3) Optional one-tap amplitude tracker before the DD carrier loop
    % ================================================================
    % The post-carrier gain tracker cannot help a DD PLL whose decisions
    % have already frozen.  This opt-in stage uses the same audited scalar
    % tracker, but owns magnitude only; phase remains exclusively owned by
    % the carrier loops.  Keeping it separate makes the H-path experiment
    % fully reversible.
    enablePreDDGainTracker = localLogical(options, ...
        'EnablePreDDGainTracker',false);
    preDDGainState = struct();
    preDDGainInfo = localEmptyGainInfo();
    xAmplitudeTracked = xPhaseTracked;
    if enablePreDDGainTracker
        preDDGainOpt = struct();
        if isfield(options,'PreDDGainTracker') && ...
                isstruct(options.PreDDGainTracker)
            preDDGainOpt = options.PreDDGainTracker;
        end
        if ~isfield(preDDGainOpt,'TrackPhase')
            preDDGainOpt.TrackPhase = false;
        end
        if ~isfield(preDDGainOpt,'TrackMagnitude')
            preDDGainOpt.TrackMagnitude = true;
        end
        if ~isfield(preDDGainOpt,'DecisionGate')
            preDDGainOpt.DecisionGate = 0.55*minDistance;
        end
        if ~isfield(preDDGainOpt,'DecisionMarginMin')
            preDDGainOpt.DecisionMarginMin = 0;
        end
        if ~isfield(preDDGainOpt,'HoldEnterBadSymbols')
            preDDGainOpt.HoldEnterBadSymbols = 16;
        end
        if ~isfield(preDDGainOpt,'RecoverGoodSymbols')
            preDDGainOpt.RecoverGoodSymbols = 1;
        end
        if ~isfield(preDDGainOpt,'PowerReference')
            preDDGainOpt.PowerReference = refPower;
        end
        if ~isfield(preDDGainOpt,'Debug')
            preDDGainOpt.Debug = debugEnabled;
        end
        [xAmplitudeTracked,preDDGainState,preDDGainInfo] = ...
            HelperTMComplexGainTracker( ...
            xPhaseTracked,refConst,preDDGainOpt);
    end

    % ================================================================
    % 4) Optional pilotless APSK ring normalization (RDE amplitude stage)
    % ================================================================
    % Magnitude tracking must precede nearest-point DD phase tracking.
    % Otherwise a one-tap fade moves symbols across ring boundaries and the
    % phase loop freezes even though its phase estimate is still useful.
    enableRingNormalizer = localLogical(options, ...
        'EnableRingNormalizer',false);
    ringState = struct();
    ringInfo = localEmptyRingInfo();
    xForDD = xAmplitudeTracked;
    if enableRingNormalizer
        ringOpt = struct();
        if isfield(options,'RingNormalizer') && ...
                isstruct(options.RingNormalizer)
            ringOpt = options.RingNormalizer;
        end
        if ~isfield(ringOpt,'PowerReference')
            ringOpt.PowerReference = refPower;
        end
        if ~isfield(ringOpt,'Debug')
            ringOpt.Debug = debugEnabled;
        end
        [xForDD,ringState,ringInfo] = ...
            HelperTMAPSKRingNormalizer(xAmplitudeTracked,refConst,ringOpt);
    end

    % ================================================================
    % 5) Optional feed-forward blind phase search (BPS)
    % ================================================================
    % Unlike the following decision-directed PLL, BPS evaluates every
    % candidate against the complete known constellation and cannot freeze
    % merely because the current hard decision crossed a narrow gate.  It
    % is kept as an independent, opt-in stage so the historical Mth/DD path
    % remains available for strict A/B regression.
    enableBlindPhaseSearch = localLogical(options, ...
        'EnableBlindPhaseSearch',false);
    blindPhaseState = struct();
    blindPhaseInfo = localEmptyBlindPhaseInfo();
    if enableBlindPhaseSearch
        blindPhaseOpt = struct();
        if isfield(options,'BlindPhaseSearch') && ...
                isstruct(options.BlindPhaseSearch)
            blindPhaseOpt = options.BlindPhaseSearch;
        end
        if ~isfield(blindPhaseOpt,'Debug')
            blindPhaseOpt.Debug = debugEnabled;
        end
        [xForDD,blindPhaseState,blindPhaseInfo] = ...
            HelperTMFeedforwardBlindPhaseSearch( ...
                xForDD,refConst,blindPhaseOpt);
    end

    % ================================================================
    % 6) Gated decision-directed PLL + HOLD/RECOVER
    % ================================================================
    yOut = complex(zeros(size(xForDD)));
    accepted = false(size(xForDD));
    fadeMask = false(size(xForDD));
    holdMask = false(size(xForDD));
    phaseErrorVec = NaN(size(xForDD));
    decisionDistance = NaN(size(xForDD));
    decisionMargin = NaN(size(xForDD));

    phaseState = 0;
    freqState = 0;
    mode = "TRACK";
    badCount = 0;
    goodCount = 0;
    holdEvents = 0;
    recoverEvents = 0;
    ddCycleSlipRejects = 0;

    % The IIR power detector sees many APSK ring amplitudes, so it must be
    % deliberately slow.  Initialize it from the first short segment rather
    % than one symbol to avoid a first-ring bias.
    pInitLen = min(max(16,round(fadeTau/2)),numel(xFF));
    powerIIR = mean(abs(xFF(1:pInitLen)).^2) + eps;
    powerReference = refPower;
    inPowerFade = false;

    useCommonSecondOrderLoop = localLogical(options, ...
        'UseCommonSecondOrderLoop',false);
    commonLoopInfo = struct();
    commonLoopState = struct();
    if useCommonSecondOrderLoop && enableDDPhaseTracker
        ignoreInnerRing = localLogical(options,'DDIgnoreInnerRing',false);
        innerRingMax = -inf;
        if ignoreInnerRing
            ddRadii = localUniqueRadii(refConst);
            if numel(ddRadii) >= 2
                innerRingMax = 0.5*(ddRadii(1)+ddRadii(2));
            end
        end
        detector = @(z,n) localAPSKDDDetector(z,n,refConst, ...
            decisionGate,decisionMarginMin,maxPhaseError,innerRingMax);
        commonOpt = struct( ...
            'SymbolRateHz',Rs, ...
            'AcquireLoopBandwidth',localNumber(options, ...
                'DDAcquireLoopBandwidth',max(0.01,loopBW)), ...
            'TrackLoopBandwidth',loopBW, ...
            'DampingFactor',damping, ...
            'InitialPhaseRad',0, ...
            'InitialFrequencyHz',0, ...
            'MaxFrequencyHz',maxResidualCFOHz, ...
            'MaxPhaseErrorRad',maxPhaseError, ...
            'LockErrorThresholdRad',localNumber(options, ...
                'DDLockErrorThresholdRad',0.12), ...
            'UnlockErrorThresholdRad',localNumber(options, ...
                'DDUnlockErrorThresholdRad',0.35), ...
            'LockSymbols',localNumber(options,'DDLockSymbols',128), ...
            'UnlockSymbols',localNumber(options,'DDUnlockSymbols',64), ...
            'MinAcquireSymbols',localNumber(options, ...
                'DDMinAcquireSymbols',256), ...
            'ErrorTauSymbols',localNumber(options, ...
                'DDErrorTauSymbols',64), ...
            'HoldEnterBadSymbols',holdEnterBad, ...
            'RecoverGoodSymbols',recoverGood, ...
            'EnableFadeHold',enableFadeHold, ...
            'FadePowerTauSymbols',fadeTau, ...
            'FadeEnterDB',fadeEnterDB, ...
            'FadeExitDB',fadeExitDB, ...
            'PowerReference',powerReference, ...
            'ResidualPhaseLimitRad',ddResidualPhaseLimit, ...
            'CollectTrace',debugEnabled, ...
            'Debug',debugEnabled, ...
            'DebugLabel',[char(modulation) ' APSK DD']);
        [yOut,commonLoopState,commonLoopInfo] = ...
            HelperTMSecondOrderCarrierLoop(xForDD,detector,commonOpt);
        accepted = commonLoopInfo.AcceptedMask;
        fadeMask = commonLoopInfo.FadeMask;
        holdMask = commonLoopInfo.HoldMask;
        phaseErrorVec = commonLoopInfo.PhaseErrorRad;
        decisionDistance = commonLoopInfo.DetectorMetric;
        decisionMargin = NaN(size(xForDD));
        phaseState = commonLoopState.PhaseRad;
        freqState = commonLoopState.FrequencyRadPerSymbol;
        mode = string(commonLoopState.Mode);
        holdEvents = commonLoopInfo.HoldEvents;
        recoverEvents = commonLoopInfo.RecoverEvents;
        ddCycleSlipRejects = commonLoopInfo.CycleSlipRejects;
        powerIIR = commonLoopState.PowerIIR;
        inPowerFade = commonLoopState.PowerFade;
    else
    for n = 1:numel(xForDD)
        % Phase output uses the current NCO state.
        z = xForDD(n) * exp(-1j*phaseState);
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

        if ~enableDDPhaseTracker
            % In the BPS-only architecture the feed-forward stage owns the
            % time-varying phase.  Keep DD decisions for diagnostics, but do
            % not let a low-acceptance feedback loop introduce cycle slips.
            accepted(n) = reliableDecision;
            continue;
        end

        phaseStateBeforeUpdate = phaseState;

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
        % When a feed-forward BPS stage is active, this PLL only owns the
        % small residual phase.  A residual state approaching a complete
        % APSK quadrant is therefore a decision-directed cycle slip, not a
        % valid channel estimate.  Reject that update and enter HOLD rather
        % than rotating all later bits by 90 degrees.  The option is off by
        % default, preserving the historical receiver exactly.
        if abs(phaseState) > ddResidualPhaseLimit
            phaseState = phaseStateBeforeUpdate;
            freqState = 0;
            if mode ~= "HOLD"
                mode = "HOLD";
                holdEvents = holdEvents + 1;
            end
            badCount = 0;
            goodCount = 0;
            holdMask(n) = true;
            accepted(n) = false;
            ddCycleSlipRejects = ddCycleSlipRejects + 1;
        end
    end
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
    info.DDPhaseTrackerEnabled = enableDDPhaseTracker;
    if useCommonSecondOrderLoop && enableDDPhaseTracker
        info.DDLoopEngine = 'common-second-order';
        info.DDAcquireLoopBandwidth = ...
            commonLoopInfo.AcquireLoopBandwidth;
        info.DDLocked = commonLoopInfo.Locked;
        info.DDLockTransitions = commonLoopInfo.LockTransitions;
        info.DDReacquisitions = commonLoopInfo.Reacquisitions;
    elseif enableDDPhaseTracker
        info.DDLoopEngine = 'embedded-legacy';
        info.DDAcquireLoopBandwidth = loopBW;
        info.DDLocked = strcmpi(char(mode),'TRACK');
        info.DDLockTransitions = 0;
        info.DDReacquisitions = 0;
    else
        info.DDLoopEngine = 'disabled';
        info.DDAcquireLoopBandwidth = NaN;
        info.DDLocked = true;
        info.DDLockTransitions = 0;
        info.DDReacquisitions = 0;
    end
    info.DDResidualPhaseLimit_deg = rad2deg(ddResidualPhaseLimit);
    info.DDCycleSlipRejects = ddCycleSlipRejects;
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
    info.MthPowerPhaseTrackerEnabled = enableMthPhaseTracker;
    info.MthPowerPhaseTrackerApplied = mthPhaseInfo.Applied;
    info.MthPowerPhaseWindowSymbols = mthPhaseInfo.WindowSymbols;
    info.MthPowerPhaseFinalCorrection_deg = ...
        mthPhaseInfo.FinalCorrection_deg;
    info.MthPowerPhaseMedianConfidence = mthPhaseInfo.MedianConfidence;
    info.PreDDGainTrackerEnabled = enablePreDDGainTracker;
    info.PreDDGainTrackerApplied = preDDGainInfo.Applied;
    info.PreDDGainAcceptanceRate = preDDGainInfo.AcceptanceRate;
    info.PreDDGainHoldFraction = preDDGainInfo.HoldFraction;
    info.PreDDGainFadeFraction = preDDGainInfo.FadeFraction;
    info.PreDDGainFinalMagnitude_dB = preDDGainInfo.FinalGainMagnitude_dB;
    info.RingNormalizerEnabled = enableRingNormalizer;
    info.RingNormalizerApplied = ringInfo.Applied;
    info.RingEstimatorMode = ringInfo.EstimatorMode;
    info.RingAcceptanceRate = ringInfo.AcceptanceRate;
    info.RingHoldFraction = ringInfo.HoldFraction;
    info.RingFadeFraction = ringInfo.FadeFraction;
    info.RingFinalAmplitude_dB = ringInfo.FinalAmplitude_dB;
    info.BlindPhaseSearchEnabled = enableBlindPhaseSearch;
    info.BlindPhaseSearchApplied = blindPhaseInfo.Applied;
    info.BlindPhaseSearchReliableFraction = ...
        blindPhaseInfo.ReliableFraction;
    info.BlindPhaseSearchMedianMetric = blindPhaseInfo.MedianBestMetric;
    info.BlindPhaseSearchFinalCorrection_deg = ...
        blindPhaseInfo.FinalCorrection_deg;

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
    state.MthPowerPhaseTracker = mthPhaseState;
    state.PreDDGainTracker = preDDGainState;
    state.RingNormalizer = ringState;
    state.BlindPhaseSearch = blindPhaseState;
    state.CommonSecondOrderLoop = commonLoopState;

    if debugEnabled
        try
            assignin('base','lastTMAPSKCarrierState',state);
            assignin('base','lastTMAPSKCarrierInfo',info);
        catch
        end
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
        blockSymbols, phaseGridSize, trimFraction, metricMax, maxCFOHz, ...
        coarseCFOHz,useGlobalPhase,applyResidualCFO)

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
        'CoarseCFOHz',coarseCFOHz, ...
        'ResidualCFOHz',0, ...
        'ResidualCFOApplied',false, ...
        'GlobalPhaseUsed',false, ...
        'GlobalPhaseRad',0, ...
        'GlobalMetric',inf, ...
        'CFOHz',0);

    if nBlocks < 3
        qualified = false;
        return;
    end

    n0 = (0:N-1).';
    coarseOmega = 2*pi*coarseCFOHz/Rs;
    x = x.*exp(-1j*coarseOmega*n0);

    % Four-fold APSK symmetry: search one fundamental pi/2 interval after
    % the FFT coarse CFO has removed almost all inter-block phase rotation.
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

    % Once the fourth-power FFT has removed nearly all carrier rotation,
    % estimate one APSK phase over the complete acquisition prefix.  This
    % has much lower data-pattern bias than selecting a phase independently
    % in every 16-symbol block.  Any remaining four-fold ambiguity is left
    % deliberately for the ASM resolver.
    globalBestMetric = inf;
    globalBestPhase = 0;
    xGlobal = x/sqrt(mean(abs(x).^2)+eps)*sqrt(refPower);
    for k = 1:numel(phaseGrid)
        phi = phaseGrid(k);
        z = xGlobal*exp(-1j*phi);
        d2 = min(abs(z-refConst.').^2,[],2);
        candidateMetric = localTrimmedMean(d2,trimFraction);
        if candidateMetric < globalBestMetric
            globalBestMetric = candidateMetric;
            globalBestPhase = phi;
        end
    end

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

    blockPhase0 = coeff(1);
    residualOmega = coeff(2);
    residualCFOHz = residualOmega*Rs/(2*pi);
    if applyResidualCFO
        omega = coarseOmega + residualOmega;
        cfoHz = coarseCFOHz + residualCFOHz;
    else
        omega = coarseOmega;
        cfoHz = coarseCFOHz;
    end
    if useGlobalPhase
        phase0 = globalBestPhase;
    else
        phase0 = blockPhase0;
    end

    acq.BlockPhaseRad = blockPhase;
    acq.BlockPhaseUnwrappedRad = phaseUnwrapped;
    acq.BlockMetric = blockMetric;
    acq.BlockCenter = blockCenter;
    acq.MedianMetric = medianMetric;
    acq.PhaseInterceptRad = phase0;
    acq.OmegaRadPerSymbol = omega;
    acq.CoarseCFOHz = coarseCFOHz;
    acq.ResidualCFOHz = residualCFOHz;
    acq.ResidualCFOApplied = logical(applyResidualCFO);
    acq.GlobalPhaseUsed = logical(useGlobalPhase);
    acq.GlobalPhaseRad = globalBestPhase;
    acq.GlobalMetric = globalBestMetric;
    acq.CFOHz = cfoHz;

    if useGlobalPhase
        phaseMetricQualified = isfinite(globalBestMetric) && ...
            globalBestMetric <= metricMax;
    else
        % A single phase over the complete acquisition prefix is not a
        % valid quality test for a time-varying H trajectory.  The block
        % metrics already test the same constellation fit locally.
        phaseMetricQualified = true;
    end
    qualified = isfinite(phase0) && isfinite(omega) && ...
        isfinite(medianMetric) && medianMetric <= metricMax && ...
        phaseMetricQualified && abs(cfoHz) <= maxCFOHz;
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

function [phaseError,reliable,distance] = localAPSKDDDetector( ...
        z,~,refConst,decisionGate,marginMin,maxPhaseError,innerRingMax)
    [dHat,d1,d2] = localNearestTwo(z,refConst);
    margin = max(0,(d2-d1)/(d2+eps));
    % Angle difference is the amplitude-normalized DD detector described
    % for APSK fine synchronization; unlike imag(z*conj(dHat)), its gain
    % does not change with the selected ring radius.
    phaseError = angle(z*conj(dHat));
    ignoreInner = isfinite(innerRingMax) && abs(dHat) <= innerRingMax;
    reliable = d1 <= decisionGate && margin >= marginMin && ...
        abs(phaseError) <= maxPhaseError && ~ignoreInner;
    distance = d1;
end

function radii = localUniqueRadii(refConst)
    raw = sort(abs(refConst(:)));
    radii = zeros(0,1);
    for k = 1:numel(raw)
        if isempty(radii) || abs(raw(k)-radii(end)) > ...
                1e-6*max(1,raw(k))
            radii(end+1,1) = raw(k); %#ok<AGROW>
        end
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

function value = localInfoNumber(s,name,defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        raw = double(s.(name));
        value = raw(1);
    end
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
        'AcquisitionRangeTolerance_Hz',NaN, ...
        'AcquisitionQualified',false, ...
        'AcquisitionPhase_deg',NaN, ...
        'AcquisitionCFO_Hz',NaN, ...
        'FourthPowerEnabled',false, ...
        'FourthPowerQualified',false, ...
        'WideRangeRingCoarseEnabled',false, ...
        'CoarsePowerOrder',NaN, ...
        'FourthPowerCFO_Hz',NaN, ...
        'FourthPowerConfidence_dB',NaN, ...
        'CoarseSelectedSymbols',NaN, ...
        'CoarseSelectionFraction',NaN, ...
        'CoarseRadiusMax',NaN, ...
        'CoarseUnambiguousMaxCFO_Hz',NaN, ...
        'NDAResidualCFO_Hz',NaN, ...
        'NDAResidualCFOApplied',false, ...
        'GlobalNDAPhaseUsed',false, ...
        'GlobalNDAPhase_deg',NaN, ...
        'GlobalNDAMetric',NaN, ...
        'AcquisitionBlockPhase_deg',zeros(0,1), ...
        'AcquisitionBlockPhaseUnwrapped_deg',zeros(0,1), ...
        'AcquisitionBlockMetric',zeros(0,1), ...
        'AcquisitionBlockCenter',zeros(0,1), ...
        'DecisionGate',NaN, ...
        'DecisionMarginMin',NaN, ...
        'DDLoopBandwidth',NaN, ...
        'DDAcquireLoopBandwidth',NaN, ...
        'DDPhaseTrackerEnabled',true, ...
        'DDLoopEngine','embedded-legacy', ...
        'DDLocked',false, ...
        'DDLockTransitions',0, ...
        'DDReacquisitions',0, ...
        'DampingFactor',NaN, ...
        'LoopAlpha',NaN, ...
        'LoopBeta',NaN, ...
        'AcceptedDecisions',0, ...
        'AcceptanceRate',0, ...
        'HoldSymbols',0, ...
        'HoldFraction',0, ...
        'HoldEvents',0, ...
        'RecoverEvents',0, ...
        'DDResidualPhaseLimit_deg',NaN, ...
        'DDCycleSlipRejects',0, ...
        'FadeSymbols',0, ...
        'FadeFraction',0, ...
        'PhaseErrorRMS_deg',NaN, ...
        'MeanAbsPhaseError_deg',NaN, ...
        'MeanDecisionDistance',NaN, ...
        'FinalResidualFrequency_Hz',NaN, ...
        'FinalResidualPhase_deg',NaN, ...
        'MthPowerPhaseTrackerEnabled',false, ...
        'MthPowerPhaseTrackerApplied',false, ...
        'MthPowerPhaseWindowSymbols',NaN, ...
        'MthPowerPhaseFinalCorrection_deg',NaN, ...
        'MthPowerPhaseMedianConfidence',NaN, ...
        'PreDDGainTrackerEnabled',false, ...
        'PreDDGainTrackerApplied',false, ...
        'PreDDGainAcceptanceRate',NaN, ...
        'PreDDGainHoldFraction',NaN, ...
        'PreDDGainFadeFraction',NaN, ...
        'PreDDGainFinalMagnitude_dB',NaN, ...
        'RingNormalizerEnabled',false, ...
        'RingNormalizerApplied',false, ...
        'RingEstimatorMode','off', ...
        'RingAcceptanceRate',NaN, ...
        'RingHoldFraction',NaN, ...
        'RingFadeFraction',NaN, ...
        'RingFinalAmplitude_dB',NaN, ...
        'BlindPhaseSearchEnabled',false, ...
        'BlindPhaseSearchApplied',false, ...
        'BlindPhaseSearchReliableFraction',NaN, ...
        'BlindPhaseSearchMedianMetric',NaN, ...
        'BlindPhaseSearchFinalCorrection_deg',NaN);
end

function info = localEmptyGainInfo()
    info = struct('Applied',false,'AcceptanceRate',NaN, ...
        'HoldFraction',NaN,'FadeFraction',NaN, ...
        'FinalGainMagnitude_dB',NaN);
end

function info = localEmptyRingInfo()
info = struct('Applied',false,'EstimatorMode','off', ...
        'AcceptanceRate',NaN, ...
        'HoldFraction',NaN,'FadeFraction',NaN, ...
        'FinalAmplitude_dB',NaN);
end

function info = localEmptyMthPhaseInfo()
    info = struct('Applied',false,'WindowSymbols',NaN, ...
        'FinalCorrection_deg',NaN,'MedianConfidence',NaN);
end

function info = localEmptyBlindPhaseInfo()
    info = struct('Applied',false,'ReliableFraction',NaN, ...
        'MedianBestMetric',NaN,'FinalCorrection_deg',NaN);
end

function info = localEmptyFourthPowerInfo()
    info = struct( ...
        'Applied',false, ...
        'Qualified',false, ...
        'PowerOrder',NaN, ...
        'CFOHz',NaN, ...
        'ConfidenceDB',NaN, ...
        'SelectedSymbols',NaN, ...
        'SelectionFraction',NaN, ...
        'RadiusMax',NaN, ...
        'UnambiguousMaxCFOHz',NaN, ...
        'RangeToleranceHz',NaN);
end

function localPrintInfo(info,decisionGate,minDistance,nAccepted,nHold,nFade)
    fprintf('\n[TM APSK pilotless carrier recovery]\n');
    fprintf('  modulation      : %s\n',info.Modulation);
    fprintf('  NDA qualified   : %d\n',info.AcquisitionQualified);
    if info.FourthPowerEnabled
        fprintf('  x^M FFT CFO     : M=%g, %+.3f Hz, confidence=%.2f dB, qualified=%d\n', ...
            info.CoarsePowerOrder,info.FourthPowerCFO_Hz,info.FourthPowerConfidence_dB, ...
            info.FourthPowerQualified);
        fprintf(['  coarse mode     : wide-ring=%d selected=%g (%.2f%%), ', ...
            'radiusMax=%.5g, unambiguous=+/-%.3f kHz\n'], ...
            info.WideRangeRingCoarseEnabled,info.CoarseSelectedSymbols, ...
            100*info.CoarseSelectionFraction,info.CoarseRadiusMax, ...
            info.CoarseUnambiguousMaxCFO_Hz/1e3);
        fprintf('  NDA residual CFO: %+.3f Hz\n',info.NDAResidualCFO_Hz);
        fprintf('  residual applied : %d\n',info.NDAResidualCFOApplied);
    end
    fprintf('  NDA CFO         : %+.3f Hz\n',info.AcquisitionCFO_Hz);
    fprintf('  NDA phase       : %+.3f deg (mod 90 deg)\n',info.AcquisitionPhase_deg);
    if info.GlobalNDAPhaseUsed
        fprintf('  global NDA phase: %+.3f deg, metric=%.5g\n', ...
            info.GlobalNDAPhase_deg,info.GlobalNDAMetric);
    end
    fprintf('  NDA metric      : %.5g / %.5g\n', ...
        info.AcquisitionMedianMetric,info.AcquisitionMetricMax);
    if info.MthPowerPhaseTrackerEnabled
        fprintf('  Mth phase track : applied=%d window=%g final=%+.2f deg confidence=%.4f\n', ...
            info.MthPowerPhaseTrackerApplied, ...
            info.MthPowerPhaseWindowSymbols, ...
            info.MthPowerPhaseFinalCorrection_deg, ...
            info.MthPowerPhaseMedianConfidence);
    end
    if info.PreDDGainTrackerEnabled
        fprintf(['  pre-DD gain      : applied=%d accept=%.2f%% ', ...
            'HOLD=%.2f%% fade=%.2f%% final=%+.3f dB\n'], ...
            info.PreDDGainTrackerApplied, ...
            100*info.PreDDGainAcceptanceRate, ...
            100*info.PreDDGainHoldFraction, ...
            100*info.PreDDGainFadeFraction, ...
            info.PreDDGainFinalMagnitude_dB);
    end
    if info.RingNormalizerEnabled
        fprintf('  APSK ring stage : mode=%s applied=%d accept=%.2f%% HOLD=%.2f%% fade=%.2f%% finalAmp=%+.2f dB\n', ...
            info.RingEstimatorMode,info.RingNormalizerApplied, ...
            100*info.RingAcceptanceRate, ...
            100*info.RingHoldFraction,100*info.RingFadeFraction, ...
            info.RingFinalAmplitude_dB);
    end
    if info.BlindPhaseSearchEnabled
        fprintf('  blind phase BPS  : applied=%d reliable=%.2f%% metric=%.5g final=%+.2f deg\n', ...
            info.BlindPhaseSearchApplied, ...
            100*info.BlindPhaseSearchReliableFraction, ...
            info.BlindPhaseSearchMedianMetric, ...
            info.BlindPhaseSearchFinalCorrection_deg);
    end
    if isfinite(decisionGate)
        fprintf('  DD gate         : %.5g (dmin %.5g), margin>=%.3f\n', ...
            decisionGate,minDistance,info.DecisionMarginMin);
    end
    fprintf(['  DD phase loop   : engine=%s enabled=%d locked=%d ', ...
        'BW(acq/track)=%.5g/%.5g, reacq=%d\n'], ...
        info.DDLoopEngine,info.DDPhaseTrackerEnabled,info.DDLocked, ...
        info.DDAcquireLoopBandwidth,info.DDLoopBandwidth, ...
        info.DDReacquisitions);
    if isfinite(info.DDResidualPhaseLimit_deg)
        fprintf('  DD slip guard   : limit=%.2f deg, rejected=%d\n', ...
            info.DDResidualPhaseLimit_deg,info.DDCycleSlipRejects);
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
