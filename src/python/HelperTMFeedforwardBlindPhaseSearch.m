function [yOut,state,info] = HelperTMFeedforwardBlindPhaseSearch( ...
        x,referenceConstellation,options)
%HELPERTMFEEDFORWARDBLINDPHASESEARCH Pilotless phase tracking for QAM/APSK.
%
%   [Y,STATE,INFO] = HelperTMFeedforwardBlindPhaseSearch(X,REF,OPTIONS)
%
% X and Y are one-sample/symbol complex streams.  The estimator tests a
% bank of phase hypotheses over one pi/2 symmetry interval, evaluates the
% moving nearest-constellation distance, and follows the winning phase on
% a continuous (unwrapped) trajectory.  Only phase is corrected.  A local
% RMS normalization is used for the metric, so the signal amplitude passed
% to the downstream equalizer is not modified.

if nargin < 3 || isempty(options)
    options = struct();
end
x = complex(x(:));
ref = complex(referenceConstellation(:));
if isempty(x)
    yOut = x;
    state = struct('FinalPhaseRad',0,'FinalFrequencyRadPerSymbol',0);
    info = localEmptyInfo();
    info.Reason = 'empty input';
    return;
end
if isempty(ref) || any(~isfinite(ref))
    error('HelperTMFeedforwardBlindPhaseSearch:InvalidReference', ...
        'referenceConstellation must contain finite complex points.');
end

ref = ref/sqrt(mean(abs(ref).^2)+eps);
numTestPhases = max(17,round(localNumber(options,'NumTestPhases',61)));
windowSymbols = max(5,round(localNumber(options,'WindowSymbols',33)));
if mod(windowSymbols,2) == 0
    windowSymbols = windowSymbols+1;
end
hopSymbols = max(1,round(localNumber(options,'HopSymbols',4)));
metricPowerWindow = max(windowSymbols,round(localNumber( ...
    options,'MetricPowerWindowSymbols',windowSymbols)));
minConfidence = max(0,localNumber(options,'MinConfidence',0.02));
fadeThresholdDB = localNumber(options,'FadeThresholdDB',-12);
enableFadeHold = localLogical(options,'EnableFadeHold',false);
fadeEnterDB = localNumber(options,'FadeEnterDB',fadeThresholdDB);
fadeExitDB = max(fadeEnterDB,localNumber(options,'FadeExitDB',fadeEnterDB+3));
fadeEnterBlocks = max(1,round(localNumber(options,'FadeEnterBlocks',2)));
fadeRecoverBlocks = max(1,round(localNumber(options,'FadeRecoverBlocks',4)));
fadeArmReliableBlocks = max(1,round(localNumber(options, ...
    'FadeArmReliableBlocks',4)));
trajectoryAlpha = min(1,max(0,localNumber( ...
    options,'TrajectoryAlpha',0.85)));
frequencyAlpha = min(1,max(0,localNumber( ...
    options,'FrequencyAlpha',0.20)));
maxInnovation = min(pi/4,max(deg2rad(2),localNumber( ...
    options,'MaxInnovationRad',deg2rad(35))));
reacquireBlocks = max(1,round(localNumber( ...
    options,'ReacquireReliableBlocks',3)));
enableInitialFrequencyEstimate = localLogical(options, ...
    'EnableInitialFrequencyEstimate',false);
initialFrequencyBlocks = max(2,round(localNumber(options, ...
    'InitialFrequencyBlocks',64)));
preserveFrequencyOnReacquire = localLogical(options, ...
    'PreserveFrequencyOnReacquire',false);
reacquirePhaseAlpha = min(1,max(0,localNumber(options, ...
    'ReacquirePhaseAlpha',1)));
maxFrequency = max(0,localNumber(options, ...
    'MaxFrequencyRadPerSymbol',0.01));
debugEnabled = localLogical(options,'Debug',false);
debugEventCount = max(0,round(localNumber(options,'DebugEventCount',0)));
preserveInitialPhase = localLogical(options,'PreserveInitialPhase',false);

minDistance = localMinimumDistance(ref);
maxMetric = localNumber(options,'MaxMetric',NaN);
if ~isfinite(maxMetric) || maxMetric <= 0
    maxMetric = (0.65*minDistance)^2;
end

% The BPS decision metric must not interpret a scalar fade as a phase
% error.  Normalize a diagnostic copy only; preserve the input amplitude
% on the actual output path.
localPower = movmean(abs(x).^2,metricPowerWindow,'Endpoints','shrink');
referencePower = median(localPower(isfinite(localPower) & localPower > 0));
if isempty(referencePower) || ~isfinite(referencePower)
    referencePower = 1;
end
xMetric = x./sqrt(max(localPower,eps))*sqrt(mean(abs(ref).^2));

centers = unique([1:hopSymbols:numel(x),numel(x)]).';
phaseStep = (pi/2)/numTestPhases;
testPhases = -pi/4 + (0:numTestPhases-1)*phaseStep;
cost = zeros(numel(centers),numTestPhases);
refRow = ref.';
for iPhase = 1:numTestPhases
    z = xMetric*exp(-1j*testPhases(iPhase));
    distance2 = abs(z-refRow).^2;
    nearestDistance2 = min(distance2,[],2);
    filteredCost = movmean(nearestDistance2,windowSymbols, ...
        'Endpoints','shrink');
    cost(:,iPhase) = filteredCost(centers);
end

[bestMetric,bestIndex] = min(cost,[],2);
measuredPhase = zeros(size(bestMetric));
confidence = zeros(size(bestMetric));
for k = 1:numel(centers)
    i0 = bestIndex(k);
    iLeft = mod(i0-2,numTestPhases)+1;
    iRight = mod(i0,numTestPhases)+1;
    cLeft = cost(k,iLeft);
    c0 = cost(k,i0);
    cRight = cost(k,iRight);
    denominator = cLeft-2*c0+cRight;
    fractionalBin = 0;
    if isfinite(denominator) && abs(denominator) > eps
        fractionalBin = 0.5*(cLeft-cRight)/denominator;
        fractionalBin = min(0.5,max(-0.5,fractionalBin));
    end
    measuredPhase(k) = testPhases(i0)+fractionalBin*phaseStep;

    % Adjacent bins describe the same minimum and are not useful as a
    % reliability competitor.  Exclude a small circular neighbourhood.
    competitor = cost(k,:);
    neighbourhood = mod((i0-2:i0+2)-1,numTestPhases)+1;
    competitor(neighbourhood) = inf;
    runner = min(competitor);
    confidence(k) = max(0,(runner-c0)/(runner+eps));
end

powerAtCenters = localPower(centers);
powerRatioAtCenters = powerAtCenters/(referencePower+eps);
powerDBAtCenters = 10*log10(max(powerRatioAtCenters,eps));
metricReliable = isfinite(bestMetric) & bestMetric <= maxMetric & ...
    confidence >= minConfidence;

% A low-power interval must not be treated as a sequence of independent
% phase observations.  Use hysteresis so a fade enters HOLD only after a
% short run below FadeEnterDB and leaves it only after several reliable
% blocks above FadeExitDB.  The legacy single-threshold behaviour remains
% available when EnableFadeHold is false (APSK callers are unaffected).
fadeHold = false(size(metricReliable));
fadeEvents = 0;
fadeRecoveries = 0;
if enableFadeHold
    inFade = false;
    fadeArmed = false;
    armCount = 0;
    enterCount = 0;
    recoverCount = 0;
    for k = 1:numel(metricReliable)
        if ~fadeArmed
            % Do not establish the initial branch or frequency state in a
            % low-power waveform prefix.  The BPS metric can look locally
            % plausible there, but its phase slope is dominated by filter
            % startup/noise and becomes a bad HOLD prediction.  Initial
            % acquisition therefore uses the same reliable-above-exit
            % condition as recovery from an established fade.
            fadeHold(k) = true;
            if metricReliable(k) && powerDBAtCenters(k) >= fadeExitDB
                armCount = armCount+1;
            else
                armCount = 0;
            end
            if armCount >= fadeArmReliableBlocks
                fadeArmed = true;
                enterCount = 0;
                firstAcquired = max(1,k-fadeArmReliableBlocks+1);
                fadeHold(firstAcquired:k) = false;
            end
            continue;
        end
        if inFade
            if metricReliable(k) && powerDBAtCenters(k) >= fadeExitDB
                recoverCount = recoverCount+1;
            else
                recoverCount = 0;
            end
            if recoverCount >= fadeRecoverBlocks
                inFade = false;
                recoverCount = 0;
                enterCount = 0;
                fadeRecoveries = fadeRecoveries+1;
            end
        else
            if powerDBAtCenters(k) <= fadeEnterDB
                enterCount = enterCount+1;
            else
                enterCount = 0;
            end
            if enterCount >= fadeEnterBlocks
                inFade = true;
                fadeEvents = fadeEvents+1;
                firstHold = max(1,k-fadeEnterBlocks+1);
                fadeHold(firstHold:k) = true;
                recoverCount = 0;
            end
        end
        fadeHold(k) = fadeHold(k) || inFade;
    end
else
    fadeHold = powerDBAtCenters < fadeThresholdDB;
end
reliable = metricReliable & ~fadeHold;

% Track one continuous phase state.  Each BPS observation is modulo pi/2;
% map it to the branch nearest the trajectory prediction.  During a fade,
% propagate the last frequency without accepting a random phase minimum.
phaseAtCenters = zeros(size(measuredPhase));
innovationAtCenters = nan(size(measuredPhase));
frequencyAtCenters = zeros(size(measuredPhase));
trackingAction = zeros(size(measuredPhase));
frequencyState = 0;
initialFrequencySamples = zeros(0,1);
if enableInitialFrequencyEstimate
    pairIndex = find(reliable(1:end-1) & reliable(2:end));
    pairIndex = pairIndex(1:min(initialFrequencyBlocks,numel(pairIndex)));
    if ~isempty(pairIndex)
        deltaCenter = centers(pairIndex+1)-centers(pairIndex);
        % The observation is modulo pi/2.  Multiplying its phase by four
        % removes that ambiguity before wrapping the phase difference.
        deltaPhase = angle(exp(1j*4*( ...
            measuredPhase(pairIndex+1)-measuredPhase(pairIndex))))/4;
        initialFrequencySamples = deltaPhase./max(deltaCenter,1);
        initialFrequencySamples = initialFrequencySamples( ...
            isfinite(initialFrequencySamples) & ...
            abs(initialFrequencySamples) <= maxFrequency);
        if ~isempty(initialFrequencySamples)
            frequencyState = median(initialFrequencySamples);
        end
    end
end
firstReliable = find(reliable,1,'first');
if isempty(firstReliable)
    firstReliable = 1;
end
phaseState = measuredPhase(firstReliable);
phaseAtCenters(1:firstReliable) = phaseState;
frequencyAtCenters(1:firstReliable) = frequencyState;
largeInnovationCount = 0;
reacquisitions = 0;
for k = firstReliable+1:numel(centers)
    deltaSymbols = max(1,centers(k)-centers(k-1));
    prediction = phaseState+frequencyState*deltaSymbols;
    measurement = measuredPhase(k) + ...
        round((prediction-measuredPhase(k))/(pi/2))*(pi/2);
    innovation = measurement-prediction;
    innovationAtCenters(k) = innovation;
    previousPhase = phaseState;
    if reliable(k)
        if abs(innovation) <= maxInnovation
            largeInnovationCount = 0;
            phaseState = prediction+trajectoryAlpha*innovation;
            measuredFrequency = (phaseState-previousPhase)/deltaSymbols;
            frequencyState = (1-frequencyAlpha)*frequencyState + ...
                frequencyAlpha*measuredFrequency;
            trackingAction(k) = 1;
        else
            % A real fading coefficient can change phase abruptly while
            % its magnitude is near zero.  Pure HOLD would reject the new
            % stable phase forever.  Require several consistent reliable
            % BPS observations, then reacquire that continuous branch.
            largeInnovationCount = largeInnovationCount+1;
            if largeInnovationCount >= reacquireBlocks
                % Keep the old unwrapped branch and carrier slope.  The old
                % implementation jumped directly to the modulo-pi/2
                % observation and reset frequency to zero.  Under a
                % persistent Doppler this made the next prediction lag and
                % allowed a false adjacent-quadrant reacquisition.  Slew
                % toward the observation while preserving the frequency
                % state instead.
                phaseState = prediction+reacquirePhaseAlpha*innovation;
                if preserveFrequencyOnReacquire
                    measuredFrequency = ...
                        (phaseState-previousPhase)/deltaSymbols;
                    frequencyState = (1-frequencyAlpha)*frequencyState + ...
                        frequencyAlpha*measuredFrequency;
                else
                    frequencyState = 0;
                end
                largeInnovationCount = 0;
                reacquisitions = reacquisitions+1;
                trackingAction(k) = 3;
            else
                phaseState = prediction;
                trackingAction(k) = 2;
            end
        end
    else
        largeInnovationCount = 0;
        phaseState = prediction;
        trackingAction(k) = -1;
    end
    frequencyState = min(max(frequencyState,-maxFrequency),maxFrequency);
    frequencyAtCenters(k) = frequencyState;
    phaseAtCenters(k) = phaseState;
end

if firstReliable > 1
    phaseAtCenters(1:firstReliable-1) = phaseAtCenters(firstReliable);
end
sampleIndex = (1:numel(x)).';
phaseTrace = interp1(centers,phaseAtCenters,sampleIndex,'linear','extrap');
anchorCount = min(numel(x),max(windowSymbols,4*hopSymbols));
anchor = median(phaseTrace(1:anchorCount));
if preserveInitialPhase
    phaseCorrection = phaseTrace-anchor;
else
    % BPS estimates the complete carrier phase modulo pi/2.  Correct that
    % complete estimate here; ASM owns only the remaining quadrant
    % ambiguity.  Preserving the initial phase leaves a constant residual
    % for a downstream DD loop and needlessly couples two carrier loops.
    phaseCorrection = phaseTrace;
end
yOut = x.*exp(-1j*phaseCorrection);

info = localEmptyInfo();
info.Applied = true;
info.Reason = 'feed-forward nearest-constellation blind phase search';
info.NumTestPhases = numTestPhases;
info.WindowSymbols = windowSymbols;
info.HopSymbols = hopSymbols;
info.MetricPowerWindowSymbols = metricPowerWindow;
info.MaxMetric = maxMetric;
info.MinConfidence = minConfidence;
info.ReliableBlocks = nnz(reliable);
info.TotalBlocks = numel(reliable);
info.ReliableFraction = mean(reliable);
info.MedianBestMetric = median(bestMetric);
info.MedianConfidence = median(confidence);
info.AnchorPhase_deg = rad2deg(anchor);
info.PreservedInitialPhase = preserveInitialPhase;
info.FinalCorrection_deg = rad2deg(phaseCorrection(end));
info.CorrectionRMS_deg = rad2deg(sqrt(mean(phaseCorrection.^2)));
info.FinalFrequencyRadPerSymbol = frequencyState;
info.Reacquisitions = reacquisitions;
info.InitialFrequencyRadPerSymbol = localMedianOrNaN( ...
    initialFrequencySamples);
info.InitialFrequency_HzPerSymbolRate = ...
    info.InitialFrequencyRadPerSymbol/(2*pi);
info.FadeHoldBlocks = nnz(fadeHold);
info.FadeEvents = fadeEvents;
info.FadeRecoveries = fadeRecoveries;
info.PreserveFrequencyOnReacquire = preserveFrequencyOnReacquire;

state = struct('FinalPhaseRad',phaseState, ...
    'FinalFrequencyRadPerSymbol',frequencyState, ...
    'PhaseAtCentersRad',phaseAtCenters, ...
    'MeasuredPhaseModuloRad',measuredPhase, ...
    'BestMetric',bestMetric, ...
    'Confidence',confidence, ...
    'InnovationRad',innovationAtCenters, ...
    'FrequencyRadPerSymbol',frequencyAtCenters, ...
    'TrackingAction',trackingAction, ...
    'PowerRatio',powerRatioAtCenters, ...
    'FadeHold',fadeHold, ...
    'Centers',centers,'Reliable',reliable);

if debugEnabled
    fprintf('\n[TM feed-forward blind phase search]\n');
    fprintf('  phases/window/hop: %d / %d / %d\n', ...
        numTestPhases,windowSymbols,hopSymbols);
    fprintf('  reliable blocks  : %d/%d = %.2f%%\n', ...
        info.ReliableBlocks,info.TotalBlocks,100*info.ReliableFraction);
    fprintf('  metric/confidence: median %.5g / %.4f\n', ...
        info.MedianBestMetric,info.MedianConfidence);
    fprintf(['  init/final freq  : %+.6g / %+.6g rad/sym ', ...
        '(init=%+.3f Hz/Rs)\n'], ...
        info.InitialFrequencyRadPerSymbol, ...
        info.FinalFrequencyRadPerSymbol, ...
        info.InitialFrequency_HzPerSymbolRate);
    fprintf(['  HOLD/reacquire   : fadeBlocks=%d events=%d ', ...
        'recoveries=%d reacquisitions=%d preserveFreq=%d\n'], ...
        info.FadeHoldBlocks,info.FadeEvents,info.FadeRecoveries, ...
        info.Reacquisitions,info.PreserveFrequencyOnReacquire);
    fprintf('  anchor/final     : %+.3f / %+.3f deg, preserved=%d\n\n', ...
        info.AnchorPhase_deg,info.FinalCorrection_deg, ...
        info.PreservedInitialPhase);
    if debugEventCount > 0
        powerRatio = powerAtCenters/(referencePower+eps);
        [~,order] = sort(powerRatio,'ascend');
        order = order(1:min(debugEventCount,numel(order)));
        order = sort(order);
        fprintf(['  lowest-power BPS blocks:\n', ...
            '    center powerDB metric conf rel measDeg trackDeg ', ...
            'innovDeg freqDegPerSym action\n']);
        for q = reshape(order,1,[])
            fprintf(['    %6d %+7.2f %.5g %.3f %d %+8.2f ', ...
                '%+9.2f %+8.2f %+8.3f %+2d\n'], ...
                centers(q),10*log10(max(powerRatio(q),eps)), ...
                bestMetric(q),confidence(q),reliable(q), ...
                rad2deg(measuredPhase(q)),rad2deg(phaseAtCenters(q)), ...
                rad2deg(innovationAtCenters(q)), ...
                rad2deg(frequencyAtCenters(q)),trackingAction(q));
        end
        fprintf('\n');
    end
end
end

function d = localMinimumDistance(ref)
d = inf;
for k = 1:numel(ref)
    delta = abs(ref(k)-ref([1:k-1,k+1:end]));
    if ~isempty(delta)
        d = min(d,min(delta));
    end
end
end

function value = localNumber(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    raw = s.(name);
    if isnumeric(raw) || islogical(raw)
        value = double(raw(1));
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
if isnumeric(raw) || islogical(raw)
    value = logical(raw(1));
else
    value = any(lower(strtrim(string(raw))) == ["true","1","yes","on"]);
end
end

function value = localMedianOrNaN(x)
if isempty(x)
    value = NaN;
else
    value = median(x);
end
end

function info = localEmptyInfo()
info = struct('Applied',false,'Reason','', ...
    'NumTestPhases',NaN,'WindowSymbols',NaN,'HopSymbols',NaN, ...
    'MetricPowerWindowSymbols',NaN,'MaxMetric',NaN, ...
    'MinConfidence',NaN,'ReliableBlocks',0,'TotalBlocks',0, ...
    'ReliableFraction',NaN,'MedianBestMetric',NaN, ...
    'MedianConfidence',NaN,'AnchorPhase_deg',NaN, ...
    'PreservedInitialPhase',false, ...
    'FinalCorrection_deg',NaN,'CorrectionRMS_deg',NaN, ...
    'FinalFrequencyRadPerSymbol',NaN,'Reacquisitions',0, ...
    'InitialFrequencyRadPerSymbol',NaN, ...
    'InitialFrequency_HzPerSymbolRate',NaN, ...
    'FadeHoldBlocks',0,'FadeEvents',0,'FadeRecoveries',0, ...
    'PreserveFrequencyOnReacquire',false);
end
