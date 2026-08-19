function [yEq, state, info] = HelperTMBlindCMAEqualizer(x, refConst, options)
%HELPERTMBLINDCMAEQUALIZER Modulation-aware blind start plus complex DD-NLMS.
%   This is an ordinary-TM, one-shot symbol-rate adaptive equalizer.  It is
%   intentionally separate from the FACM pilot/DFE equalizers and from the
%   known-H MMSE equalizer.
%
%   The equalizer is enabled by the caller only for explicit adaptive modes
%   (blind-cma-lms or the post-carrier dd-nlms diagnostic).
%   The automatic blind cost is CMA for constant-envelope PSK, MMA for QAM
%   and UQPSK's unequal rectangular four-point constellation, and
%   radius-directed equalization (RDE) for APSK.  The update equations
%   include:
%       y(n) = w(n)'*x(n)
%       w    = w + muCMA*x(n)*conj(y(n))*(R2-|y(n)|^2)/||x(n)||^2
%       w    = w + muDD*x(n)*conj(d(n)-y(n))/||x(n)||^2
%   where d(n) is the nearest point in refConst and the DD update is gated
%   by a decision-distance threshold.  RDE selects a ring from the current
%   equalizer output, never from an unequalized input sample.  All updates
%   retain one complex tap vector so phase rotation and I/Q cross-coupling
%   are equalized together.

    x = complex(x(:));
    refConst = complex(refConst(:));
    if isempty(x)
        yEq = x;
        state = struct('Weights',complex(1));
        info = localEmptyInfo();
        info.Reason = 'empty input';
        return;
    end
    if isempty(refConst) || any(~isfinite(refConst))
        yEq = x;
        state = struct('Weights',complex(1));
        info = localEmptyInfo();
        info.Reason = 'empty or invalid reference constellation';
        return;
    end

    nTaps = localNumber(options, 'adaptiveEqualizerTaps', 11);
    nTaps = max(1, round(nTaps));
    if nTaps > 1 && mod(nTaps, 2) == 0
        nTaps = nTaps + 1;
    end
    delay = floor(nTaps/2);

    muCMA = localNumber(options, 'adaptiveEqualizerCMAStep', 0.01);
    muDD = localNumber(options, 'adaptiveEqualizerDDStep', 1e-3);
    cmaSymbols = localNumber(options, 'adaptiveEqualizerCMAWarmupSymbols', 2000);
    cmaSymbols = max(0, min(numel(x), round(cmaSymbols)));
    % Zero is an intentional diagnostic/production setting: retain the CMA
    % output and do not perform decision-directed tracking.  Do not coerce it
    % to one pass, otherwise a "CMA only" comparison silently still runs DD.
    ddPasses = max(0, round(localNumber(options, 'adaptiveEqualizerDDPasses', 1)));
    epsNorm = localNumber(options, 'adaptiveEqualizerEpsilon', 1e-8);
    epsNorm = max(epsNorm, 1e-12);
    stage = lower(localString(options, 'adaptiveEqualizerStage', 'full'));
    runCMA = ~strcmp(stage, 'dd');
    blindCostMode = localBlindCostMode(options, refConst);

    refPower = mean(abs(refConst).^2) + eps;
    inputPower = mean(abs(x).^2) + eps;
    xNorm = x * sqrt(refPower/inputPower);
    R2 = mean(abs(refConst).^4) / refPower;
    ringRadii = unique(round(abs(refConst)*1e12)/1e12);
    mmaRInphase = mean(real(refConst).^4) / ...
        max(mean(real(refConst).^2), eps);
    mmaRQuadrature = mean(imag(refConst).^4) / ...
        max(mean(imag(refConst).^2), eps);
    minDistance = localMinimumDistance(refConst);
    gate = localNumber(options, 'adaptiveEqualizerDecisionGate', NaN);
    if ~isfinite(gate) || gate <= 0
        % Stay strictly inside the nearest-neighbour decision boundary.
        gate = 0.35 * minDistance;
    end
    % DMEQU-style mode control: DD-NLMS is only safe after the blind stage
    % has entered a reliable constellation basin.  A fixed CMA duration is
    % retained as the maximum acquisition budget, but it is no longer, by
    % itself, treated as proof of convergence.
    switchMSE = localNumber(options, ...
        'adaptiveEqualizerCMASwitchMSE', NaN);
    if ~isfinite(switchMSE) || switchMSE <= 0
        switchMSE = gate^2;
    end
    minCMAConfidence = localNumber(options, ...
        'adaptiveEqualizerMinCMAConfidence', 0.50);
    minCMAConfidence = min(max(minCMAConfidence,0),1);
    requireCMAConvergence = localLogical(options, ...
        'adaptiveEqualizerRequireCMAConvergence', true);
    qualityGuardEnabled = localLogical(options, ...
        'adaptiveEqualizerQualityGuard', true);
    maxMSEDegradation = localNumber(options, ...
        'adaptiveEqualizerMaxMSEDegradation', 0.10);
    maxMSEDegradation = max(maxMSEDegradation,0);
    mseDegradationMargin = localNumber(options, ...
        'adaptiveEqualizerMSEDegradationMargin', 1e-3*refPower);
    mseDegradationMargin = max(mseDegradationMargin,0);
    maxTapNorm = localNumber(options, 'adaptiveEqualizerMaxTapNorm', 4);
    maxTapNorm = max(maxTapNorm, 1);

    % DMEQU protection controls.  The legacy helper used one fixed CMA
    % block followed by DD over the complete capture.  That is unsafe for
    % an effectively single-path H snapshot: the extra taps can manufacture
    % ISI and a short burst of wrong decisions can move all taps together.
    % Keep the public 11-tap default, but select a scalar path after blind
    % acquisition and supervise DD in short windows.
    sideTapOnRatio = localNumber(options, ...
        'adaptiveEqualizerScalarSideTapOnRatio', 0.02);
    sideTapOnRatio = min(max(sideTapOnRatio,0),1);
    ddWindowSymbols = max(32, round(localNumber(options, ...
        'adaptiveEqualizerDDWindowSymbols', 256)));
    ddMinWindowAcceptance = localNumber(options, ...
        'adaptiveEqualizerDDMinWindowAcceptance', 0.75);
    ddMinWindowAcceptance = min(max(ddMinWindowAcceptance,0),1);
    scalarDDPasses = round(localNumber(options, ...
        'adaptiveEqualizerScalarDDPasses', -1));
    modulationName = localString(options,'modType','');
    if isempty(modulationName)
        modulationName = localString(options,'modulationName','');
    end
    modulationName = upper(string(modulationName));
    autoScalarForQAM = localLogical(options, ...
        'adaptiveEqualizerAutoScalarForQAM', false);
    autoScalarAllowed = contains(modulationName,'APSK') || ...
        (contains(modulationName,'QAM') && autoScalarForQAM);
    enableQAMWindowHold = localLogical(options, ...
        'adaptiveEqualizerEnableQAMWindowHold', false);
    if contains(modulationName,'QAM') && ~enableQAMWindowHold
        % Preserve the validated legacy QAM DD trajectory until the
        % pilot/sector-slip guard is enabled.  The window counters still
        % provide diagnostics, but do not alter QAM output by default.
        ddMinWindowAcceptance = 0;
    end
    enableFadeHold = localLogical(options, ...
        'adaptiveEqualizerEnableFadeHold', true);
    if contains(modulationName,'QAM') && ~enableQAMWindowHold
        enableFadeHold = false;
    end
    fadeHoldDB = localNumber(options, ...
        'adaptiveEqualizerFadeHoldDB', -12);
    fadeHoldPowerRatio = 10^(min(fadeHoldDB,0)/10);

    % A front-end stage (currently the APSK pilot estimator) may observe a
    % fade before envelope normalization hides it.  Accept an exactly
    % symbol-aligned mask and expand it by the FIR span so no DD update uses
    % a tap vector contaminated by a marked sample.  A length mismatch is
    % deliberately ignored and reported rather than silently re-indexed.
    externalFadeMask = false(numel(xNorm),1);
    externalFadeMaskProvided = isfield(options, ...
        'adaptiveEqualizerExternalFadeMask') && ...
        ~isempty(options.adaptiveEqualizerExternalFadeMask);
    externalFadeMaskInputLength = 0;
    externalFadeMaskLengthMatched = false;
    externalFadeInputSymbols = 0;
    externalFadeExpandedSymbols = 0;
    if externalFadeMaskProvided
        externalFadeMaskRaw = logical( ...
            options.adaptiveEqualizerExternalFadeMask(:));
        externalFadeMaskInputLength = numel(externalFadeMaskRaw);
        externalFadeMaskLengthMatched = ...
            externalFadeMaskInputLength == numel(xNorm);
        if externalFadeMaskLengthMatched
            externalFadeInputSymbols = nnz(externalFadeMaskRaw);
            if nTaps > 1 && externalFadeInputSymbols > 0
                externalFadeMask = conv(double(externalFadeMaskRaw), ...
                    ones(nTaps,1),'same') > 0;
            else
                externalFadeMask = externalFadeMaskRaw;
            end
            externalFadeExpandedSymbols = nnz(externalFadeMask);
        end
    end

    w = complex(zeros(nTaps,1));
    w(delay+1) = 1;
    yEq = xNorm;
    cmaError = NaN(numel(x),1);
    ddError = NaN(numel(x),1);
    accepted = false(numel(x),1);
    rejected = false(numel(x),1);
    valid = (delay+1):(numel(x)-delay);

    if isempty(valid)
        state = struct('Weights',w);
        info = localEmptyInfo();
        info.Reason = 'input shorter than equalizer span';
        return;
    end

    phaseRotation = 0;
    phaseScore = NaN;
    phaseConfidence = NaN;
    cmaQualified = ~runCMA;
    scalarMode = (nTaps == 1);
    sideTapEnergyRatio = 0;
    ddHoldWindows = 0;
    ddFadeHoldWindows = 0;
    ddExternalFadeHoldWindows = 0;
    ddExternalFadeHoldSymbols = 0;
    ddGoodWindows = 0;
    ddWindowCount = 0;
    ddHoldReason = '';

    if runCMA
        % Blind startup.  The cost is selected from the known modulation
        % constellation, but no transmitted symbols or BER feedback are used.
        cmaLast = min(valid(end), valid(1) + cmaSymbols - 1);
        for n = valid(1):cmaLast
            xv = xNorm(n+delay:-1:n-delay);
            powerX = real(xv' * xv) + epsNorm;
            y = w' * xv;
            switch blindCostMode
                case 'rde'
                    [~, ringIndex] = min(abs(abs(y)-ringRadii));
                    targetRadius2 = ringRadii(ringIndex)^2;
                    blindError = targetRadius2 - abs(y)^2;
                    tapGradientError = y * blindError;
                    cmaError(n) = abs(blindError)^2;
                case 'mma'
                    errorInphase = mmaRInphase - real(y)^2;
                    errorQuadrature = mmaRQuadrature - imag(y)^2;
                    tapGradientError = real(y)*errorInphase + ...
                        1j*imag(y)*errorQuadrature;
                    cmaError(n) = abs(errorInphase)^2 + ...
                        abs(errorQuadrature)^2;
                otherwise
                    blindError = R2 - abs(y)^2;
                    tapGradientError = y * blindError;
                    cmaError(n) = abs(blindError)^2;
            end
            w = w + (muCMA / powerX) * xv * conj(tapGradientError);
            if any(~isfinite(w))
                w(:) = 0;
                w(delay+1) = 1;
                break;
            end
        end

        % CMA has an unavoidable phase ambiguity.  Resolve it without TX
        % bits by choosing the rotational hypothesis with the smallest
        % constellation-structure score.
        phaseOrder = localPhaseOrder(options, refConst);
        phaseCandidates = (0:phaseOrder-1) * (2*pi/phaseOrder);
        score = inf(size(phaseCandidates));
        phaseSymbols = valid(1):min(valid(end),valid(1)+max(32,cmaSymbols)-1);
        yPhase = zeros(numel(phaseSymbols),1);
        for k = 1:numel(phaseSymbols)
            n = phaseSymbols(k);
            xv = xNorm(n+delay:-1:n-delay);
            yPhase(k) = w' * xv;
        end
        for k = 1:numel(phaseCandidates)
            z = yPhase * exp(1j*phaseCandidates(k));
            score(k) = mean(min(abs(z-refConst.').^2,[],2));
        end
        [phaseScore, phaseIndex] = min(score);
        phaseRotation = phaseCandidates(phaseIndex);
        phaseDistance = min(abs( ...
            yPhase*exp(1j*phaseRotation)-refConst.'),[],2);
        phaseConfidence = mean(phaseDistance <= gate);
        cmaQualified = isfinite(phaseScore) && ...
            phaseScore <= switchMSE && ...
            phaseConfidence >= minCMAConfidence;
        w = w * exp(-1j*phaseRotation);

        % A scalar H path should not be forced through a full FIR/DD
        % tracker.  Estimate the energy outside the dominant tap after the
        % blind stage.  The thresholds have hysteresis so a noisy estimate
        % cannot switch the structure on every capture.
        centerEnergy = abs(w(delay+1)).^2;
        totalEnergy = sum(abs(w).^2) + eps;
        sideTapEnergyRatio = max(0, (totalEnergy-centerEnergy)/totalEnergy);
        scalarMode = scalarMode || (autoScalarAllowed && ...
            sideTapEnergyRatio <= sideTapOnRatio);
        if scalarMode && nTaps > 1
            centerTap = w(delay+1);
            w(:) = 0;
            w(delay+1) = centerTap;
            if abs(w(delay+1)) < eps
                w(delay+1) = 1;
            end
        end
    else
        cmaLast = valid(1)-1;
        phaseOrder = localPhaseOrder(options, refConst);
        phaseCandidates = (0:phaseOrder-1) * (2*pi/phaseOrder);
    end

    ddPassesRequested = ddPasses;
    ddPassesEffective = ddPasses;
    if runCMA && requireCMAConvergence && ~cmaQualified
        ddPassesEffective = 0;
    end

    % APSK already has a ring-directed blind stage and (in ordinary TM)
    % pilot-based complex correction before this helper.  On a scalar path,
    % allowing an unanchored nearest-point DD loop to run is more likely to
    % create a sector slip than to remove ISI.  QAM keeps DD because the
    % short A/B tests show that it is needed when residual structure remains.
    if scalarMode && scalarDDPasses >= 0
        ddPassesEffective = min(ddPassesEffective, scalarDDPasses);
    elseif scalarMode && contains(modulationName,'APSK')
        ddPassesEffective = 0;
    end

    if ddPassesEffective == 0
        if runCMA
            % Blind-only diagnostic mode: filter with the startup taps,
            % but leave the taps fixed.
            for n = valid
                xv = xNorm(n+delay:-1:n-delay);
                yEq(n) = w' * xv;
            end
        end
    else
        % Decision-directed complex NLMS tracking.  Each window has a
        % last-good tap snapshot.  If decisions become unreliable, restore
        % that snapshot and render the window with the stable taps instead of
        % letting a burst of wrong decisions poison the rest of the block.
        for pass = 1:ddPassesEffective %#ok<NASGU>
            lastGoodW = w;
            passStart = valid(1);
            while passStart <= valid(end)
                passEnd = min(valid(end), passStart + ddWindowSymbols - 1);
                windowAccepted = 0;
                windowDecisions = 0;
                windowW = w;
                windowPowerRatio = mean(abs(xNorm(passStart:passEnd)).^2) / ...
                    max(refPower,eps);
                powerFadeWindow = enableFadeHold && ...
                    isfinite(windowPowerRatio) && ...
                    windowPowerRatio < fadeHoldPowerRatio;
                externalFadeWindow = externalFadeMaskLengthMatched && ...
                    any(externalFadeMask(passStart:passEnd));
                if powerFadeWindow || externalFadeWindow
                    w = lastGoodW;
                    ddHoldWindows = ddHoldWindows + 1;
                    if powerFadeWindow
                        ddFadeHoldWindows = ddFadeHoldWindows + 1;
                    end
                    if externalFadeWindow
                        ddExternalFadeHoldWindows = ...
                            ddExternalFadeHoldWindows + 1;
                        ddExternalFadeHoldSymbols = ...
                            ddExternalFadeHoldSymbols + ...
                            (passEnd-passStart+1);
                    end
                    if isempty(ddHoldReason)
                        if externalFadeWindow && powerFadeWindow
                            ddHoldReason = sprintf([ ...
                                'external fade mask and DD window power ', ...
                                '%.2f dB below %.2f dB'], ...
                                10*log10(max(windowPowerRatio,eps)),fadeHoldDB);
                        elseif externalFadeWindow
                            ddHoldReason = ...
                                'external pilot-derived fade mask';
                        else
                            ddHoldReason = sprintf(...
                                'DD window power %.2f dB below %.2f dB', ...
                                10*log10(max(windowPowerRatio,eps)),fadeHoldDB);
                        end
                    end
                    for n = passStart:passEnd
                        xv = xNorm(n+delay:-1:n-delay);
                        yEq(n) = w' * xv;
                    end
                    ddWindowCount = ddWindowCount + 1;
                    passStart = passEnd + 1;
                    continue;
                end
                for n = passStart:passEnd
                    xv = xNorm(n+delay:-1:n-delay);
                    powerX = real(xv' * xv) + epsNorm;
                    y = w' * xv;
                    yEq(n) = y;
                    distance = abs(y - refConst);
                    [~, idx] = min(distance);
                    dHat = refConst(idx);
                    errDD = dHat - y;
                    ddError(n) = abs(errDD)^2;
                    decisionOK = abs(errDD) <= gate;
                    windowDecisions = windowDecisions + 1;
                    if decisionOK
                        wCandidate = w + (muDD / powerX) * xv * conj(errDD);
                        if all(isfinite(wCandidate)) && norm(wCandidate) <= maxTapNorm
                            w = wCandidate;
                            accepted(n) = true;
                            windowAccepted = windowAccepted + 1;
                        else
                            rejected(n) = true;
                        end
                    else
                        rejected(n) = true;
                    end
                    if any(~isfinite(w))
                        w = windowW;
                        rejected(n) = true;
                        break;
                    end
                end

                ddWindowCount = ddWindowCount + 1;
                windowRate = windowAccepted / max(windowDecisions,1);
                if windowRate >= ddMinWindowAcceptance
                    lastGoodW = w;
                    ddGoodWindows = ddGoodWindows + 1;
                else
                    w = lastGoodW;
                    ddHoldWindows = ddHoldWindows + 1;
                    if isempty(ddHoldReason)
                        ddHoldReason = sprintf(...
                            'DD window acceptance %.3f below %.3f', ...
                            windowRate,ddMinWindowAcceptance);
                    end
                    % Re-render the rejected window with the last stable
                    % taps.  This is a one-shot approximation of HOLD and
                    % keeps the output causal with respect to the snapshot.
                    for n = passStart:passEnd
                        xv = xNorm(n+delay:-1:n-delay);
                        yEq(n) = w' * xv;
                    end
                end
                passStart = passEnd + 1;
            end
        end
    end

    % Keep the causal output generated inside the tracking loop.  Do not
    % re-run the complete block with the final tap vector: that would erase
    % the tap evolution and apply the end-of-block equalizer to samples from
    % the beginning of a time-varying channel.  The DD loop already writes
    % yEq(n) using the tap vector valid at time n.
    yEq(1:delay) = xNorm(1:delay);
    yEq(numel(x)-delay+1:end) = xNorm(numel(x)-delay+1:end);

    % A blind cost can decrease while the useful constellation structure
    % gets worse (a local minimum / false lock).  Compare input and output
    % using only modulation geometry, never TX bits or BER, and roll back a
    % materially harmful equalizer result.  This is especially important
    % for flat or effectively single-tap H snapshots where equalization is
    % unnecessary and DD updates can otherwise manufacture ISI.
    inputStructureMSE = localBestStructureMSE( ...
        xNorm(valid),refConst,phaseCandidates);
    outputStructureMSE = localBestStructureMSE( ...
        yEq(valid),refConst,phaseCandidates);
    qualityImprovement = NaN;
    if isfinite(inputStructureMSE) && inputStructureMSE > eps
        qualityImprovement = ...
            (inputStructureMSE-outputStructureMSE)/inputStructureMSE;
    end
    outputAccepted = true;
    rollbackReason = '';
    if qualityGuardEnabled && isfinite(inputStructureMSE) && ...
            isfinite(outputStructureMSE) && ...
            outputStructureMSE > ...
            inputStructureMSE*(1+maxMSEDegradation) + ...
            mseDegradationMargin
        yEq = xNorm;
        w(:) = 0;
        w(delay+1) = 1;
        outputAccepted = false;
        rollbackReason = sprintf( ...
            ['constellation MSE degraded from %.4g to %.4g; ', ...
             'adaptive output rolled back'], ...
            inputStructureMSE,outputStructureMSE);
    end

    state = struct('Weights',w,'Delay',delay,'NumTaps',nTaps);
    info = localEmptyInfo();
    info.Enabled = true;
    info.Mode = 'blind-cma-lms';
    info.NumTaps = nTaps;
    info.CMADelay = delay;
    info.CMASymbols = max(0, cmaLast - valid(1) + 1);
    info.DDPasses = ddPassesEffective;
    info.DDPassesRequested = ddPassesRequested;
    info.CMAStep = muCMA;
    info.DDStep = muDD;
    info.CMAR2 = R2;
    if ~runCMA
        info.BlindCostMode = 'dd-only';
    else
        info.BlindCostMode = blindCostMode;
    end
    info.DecisionGate = gate;
    info.CMASwitchMSE = switchMSE;
    info.CMAConfidenceRate = phaseConfidence;
    info.CMAQualified = logical(cmaQualified);
    info.PhaseRotation_deg = phaseRotation * 180/pi;
    info.PhaseStructureScore = phaseScore;
    info.InputPower = inputPower;
    info.OutputPower = mean(abs(yEq).^2);
    info.AcceptedDecisions = nnz(accepted);
    info.RejectedDecisions = nnz(rejected);
    info.DecisionCount = numel(valid) * ddPassesEffective;
    if info.DecisionCount > 0
        info.AcceptanceRate = info.AcceptedDecisions / info.DecisionCount;
    else
        info.AcceptanceRate = NaN;
    end
    info.CMAMSE = localFiniteMean(cmaError);
    info.DDMSE = localFiniteMean(ddError);
    info.FinalTapNorm = norm(w);
    if scalarMode
        info.EqualizerStructure = 'scalar';
    else
        info.EqualizerStructure = 'fir';
    end
    info.SideTapEnergyRatio = sideTapEnergyRatio;
    info.DDWindowSymbols = ddWindowSymbols;
    info.DDMinWindowAcceptance = ddMinWindowAcceptance;
    info.DDWindowCount = ddWindowCount;
    info.DDGoodWindows = ddGoodWindows;
    info.DDHoldWindows = ddHoldWindows;
    info.DDFadeHoldWindows = ddFadeHoldWindows;
    info.ExternalFadeMaskProvided = logical(externalFadeMaskProvided);
    info.ExternalFadeMaskLengthMatched = ...
        logical(externalFadeMaskLengthMatched);
    info.ExternalFadeMaskInputLength = externalFadeMaskInputLength;
    info.ExternalFadeInputSymbols = externalFadeInputSymbols;
    info.ExternalFadeExpandedSymbols = externalFadeExpandedSymbols;
    info.DDExternalFadeHoldWindows = ddExternalFadeHoldWindows;
    info.DDExternalFadeHoldSymbols = ddExternalFadeHoldSymbols;
    info.FadeHoldDB = fadeHoldDB;
    info.DDHoldReason = ddHoldReason;
    info.InputStructureMSE = inputStructureMSE;
    info.OutputStructureMSE = outputStructureMSE;
    info.QualityImprovement = qualityImprovement;
    info.OutputAccepted = logical(outputAccepted);
    info.RollbackReason = rollbackReason;
    if ddPassesEffective == 0
        info.Converged = ~runCMA || isfinite(info.CMAMSE);
    elseif runCMA
        info.Converged = isfinite(info.CMAMSE) && isfinite(info.DDMSE);
    else
        info.Converged = isfinite(info.DDMSE);
    end
    info.Converged = info.Converged && all(isfinite(yEq)) && ...
        (~runCMA || cmaQualified) && outputAccepted;
    if ~outputAccepted
        info.Reason = rollbackReason;
    elseif ddPassesRequested > 0 && ddPassesEffective == 0 && runCMA
        info.Reason = sprintf( ...
            ['%s blind startup retained; CMA qualification failed ', ...
             '(MSE %.4g/%.4g, confidence %.1f%%/%.1f%%)'], ...
            upper(blindCostMode),phaseScore,switchMSE, ...
            100*phaseConfidence,100*minCMAConfidence);
    elseif ddPassesEffective == 0 && runCMA
        info.Reason = sprintf('%s blind startup only', upper(blindCostMode));
    elseif ddPassesEffective == 0
        info.Reason = 'DD tracking disabled; input retained';
    elseif runCMA
        info.Reason = sprintf('%s blind startup + complex DD-NLMS', ...
            upper(blindCostMode));
    else
        info.Reason = 'complex DD-NLMS only';
    end
end

function mode = localBlindCostMode(options, refConst)
    requested = lower(strtrim(localString( ...
        options, 'adaptiveEqualizerBlindCostMode', 'auto')));
    if any(strcmp(requested, {'cma','mma','rde'}))
        mode = requested;
        return;
    end

    modulation = upper(string(localString(options, 'modType', '')));
    if contains(modulation, 'APSK')
        mode = 'rde';
    elseif contains(modulation, 'QAM') || contains(modulation, 'UQPSK')
        % UQPSK has a rectangular four-point reference constellation with
        % unequal I/Q marginal amplitudes.  For the current [+-1,+-j/2]
        % mapping all four points have the same total modulus, so CMA is
        % not mathematically invalid; MMA is selected because its separate
        % real-axis targets retain the rectangle's anisotropic geometry.
        mode = 'mma';
    elseif localIsConstantEnvelope(refConst)
        mode = 'cma';
    else
        % Unknown multi-amplitude constellations retain the conservative
        % historical target unless the caller explicitly selects MMA/RDE.
        mode = 'cma';
    end
end

function tf = localIsConstantEnvelope(refConst)
    radius2 = abs(refConst).^2;
    tf = max(radius2)-min(radius2) <= ...
        max(1e-10, 1e-6*mean(radius2));
end

function info = localEmptyInfo()
    info = struct( ...
        'Enabled',false, ...
        'Mode','off', ...
        'NumTaps',0, ...
        'CMADelay',0, ...
        'CMASymbols',0, ...
        'DDPasses',0, ...
        'DDPassesRequested',0, ...
        'CMAStep',NaN, ...
        'DDStep',NaN, ...
        'CMAR2',NaN, ...
        'BlindCostMode','off', ...
        'DecisionGate',NaN, ...
        'CMASwitchMSE',NaN, ...
        'CMAConfidenceRate',NaN, ...
        'CMAQualified',false, ...
        'PhaseRotation_deg',NaN, ...
        'PhaseStructureScore',NaN, ...
        'InputPower',NaN, ...
        'OutputPower',NaN, ...
        'AcceptedDecisions',0, ...
        'RejectedDecisions',0, ...
        'DecisionCount',0, ...
        'AcceptanceRate',NaN, ...
        'CMAMSE',NaN, ...
        'DDMSE',NaN, ...
        'FinalTapNorm',NaN, ...
        'EqualizerStructure','off', ...
        'SideTapEnergyRatio',NaN, ...
        'DDWindowSymbols',0, ...
        'DDMinWindowAcceptance',NaN, ...
        'DDWindowCount',0, ...
        'DDGoodWindows',0, ...
        'DDHoldWindows',0, ...
        'DDFadeHoldWindows',0, ...
        'ExternalFadeMaskProvided',false, ...
        'ExternalFadeMaskLengthMatched',false, ...
        'ExternalFadeMaskInputLength',0, ...
        'ExternalFadeInputSymbols',0, ...
        'ExternalFadeExpandedSymbols',0, ...
        'DDExternalFadeHoldWindows',0, ...
        'DDExternalFadeHoldSymbols',0, ...
        'FadeHoldDB',NaN, ...
        'DDHoldReason','', ...
        'InputStructureMSE',NaN, ...
        'OutputStructureMSE',NaN, ...
        'QualityImprovement',NaN, ...
        'OutputAccepted',false, ...
        'RollbackReason','', ...
        'Converged',false, ...
        'Reason','disabled');
end

function value = localNumber(options, name, defaultValue)
    value = defaultValue;
    if nargin >= 1 && isstruct(options) && isfield(options, name) && ...
            ~isempty(options.(name))
        raw = options.(name);
        if isnumeric(raw) || islogical(raw)
            candidate = double(raw(1));
        else
            candidate = str2double(string(raw));
        end
        if isfinite(candidate)
            value = candidate;
        end
    end
end

function value = localString(options, name, defaultValue)
    value = char(defaultValue);
    if isstruct(options) && isfield(options,name) && ~isempty(options.(name))
        value = char(string(options.(name)));
    end
end

function value = localLogical(options, name, defaultValue)
    value = logical(defaultValue);
    if ~isstruct(options) || ~isfield(options,name) || ...
            isempty(options.(name))
        return;
    end
    raw = options.(name);
    if islogical(raw) || isnumeric(raw)
        value = logical(raw(1));
        return;
    end
    token = lower(strtrim(char(string(raw))));
    if any(strcmp(token,{'1','true','yes','on'}))
        value = true;
    elseif any(strcmp(token,{'0','false','no','off'}))
        value = false;
    end
end

function score = localBestStructureMSE(symbols,refConst,phaseCandidates)
    symbols = complex(symbols(:));
    symbols = symbols(isfinite(real(symbols)) & isfinite(imag(symbols)));
    score = NaN;
    if isempty(symbols) || isempty(refConst)
        return;
    end
    % Keep this production guard bounded for long high-rate captures while
    % retaining samples from the complete observation interval.
    maxScoreSymbols = 20000;
    if numel(symbols) > maxScoreSymbols
        index = unique(round(linspace(1,numel(symbols),maxScoreSymbols)));
        symbols = symbols(index);
    end
    symbols = symbols * sqrt( ...
        mean(abs(refConst).^2)/(mean(abs(symbols).^2)+eps));
    scores = inf(size(phaseCandidates));
    for k = 1:numel(phaseCandidates)
        z = symbols * exp(1j*phaseCandidates(k));
        scores(k) = mean(min(abs(z-refConst.').^2,[],2));
    end
    score = min(scores);
end

function value = localMinimumDistance(refConst)
    if numel(refConst) < 2
        value = 1;
        return;
    end
    delta = abs(refConst(:) - refConst(:).');
    delta(delta == 0) = Inf;
    value = min(delta(:));
    if ~isfinite(value) || value <= 0
        value = 1;
    end
end

function order = localPhaseOrder(options, refConst)
    order = 4;
    if numel(refConst) == 2
        order = 2;
    elseif numel(refConst) == 8
        order = 8;
    end
    if isstruct(options) && isfield(options, 'adaptiveEqualizerPhaseOrder') && ...
            ~isempty(options.adaptiveEqualizerPhaseOrder)
        candidate = round(double(options.adaptiveEqualizerPhaseOrder));
        if isfinite(candidate) && candidate >= 2 && candidate <= 16
            order = candidate;
        end
    end
end

function value = localFiniteMean(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = mean(values);
    end
end
