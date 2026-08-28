function [yOut,state,info] = HelperTMAPSKMthPowerPhaseTracker(x,powerOrder,options)
%HELPERTMAPSKMTHPOWERPHASETRACKER NDA time-varying APSK phase tracker.
%
%   [Y,STATE,INFO] = HelperTMAPSKMthPowerPhaseTracker(X,M,OPTIONS)
%
% X is the one-sample/symbol stream after coarse CFO and initial NDA phase
% acquisition.  M is the least common multiple of the APSK ring sizes
% (12 for CCSDS 16APSK, 48 for CCSDS 32APSK).  A causal moving average of
% (x/|x|)^M estimates the changing phase without symbol decisions.  A
% second-order loop follows that phasor with prediction during low-confidence
% fades.  Tracking one continuous M-domain state is important: independently
% unwrapping/interpolating reliable islands can select different 2*pi/M
% branches (7.5 degrees for 32APSK) after every fade.  Only the phase CHANGE
% relative to the acquisition prefix is removed, so this helper does not
% create a new M-fold absolute ambiguity; the existing NDA phase and later
% ASM remain responsible for absolute orientation.

if nargin < 2 || isempty(powerOrder)
    powerOrder = 4;
end
if nargin < 3 || isempty(options)
    options = struct();
end
x = complex(x(:));
M = max(1,round(double(powerOrder)));
if isempty(x)
    yOut = x;
    state = struct('FinalPhaseRad',0,'PowerOrder',M);
    info = localEmptyInfo();
    info.Reason = 'empty input';
    return;
end

windowSymbols = max(4,round(localNumber(options,'WindowSymbols',64)));
amplitudeFloorRatio = max(0,localNumber(options,'AmplitudeFloorRatio',0.05));
minConfidence = max(0,localNumber(options,'MinConfidence',0.15));
loopBandwidth = localNumber(options,'LoopBandwidth',0.01);
damping = localNumber(options,'DampingFactor',1/sqrt(2));
maxRaisedFrequency = max(0,localNumber(options, ...
    'MaxRaisedFrequencyRadPerSymbol',0.25));
initialFrequencySymbols = max(8,round(localNumber(options, ...
    'InitialFrequencySymbols',512)));
debugEnabled = localLogical(options,'Debug',false);
if ~isfinite(loopBandwidth) || loopBandwidth <= 0 || loopBandwidth > 0.2
    error('HelperTMAPSKMthPowerPhaseTracker:InvalidLoopBandwidth', ...
        'LoopBandwidth must be in (0,0.2].');
end
if ~isfinite(damping) || damping <= 0
    error('HelperTMAPSKMthPowerPhaseTracker:InvalidDamping', ...
        'DampingFactor must be positive.');
end

mag = abs(x);
medianMag = median(mag(mag > 0));
if isempty(medianMag) || ~isfinite(medianMag)
    medianMag = 1;
end
floorMag = max(sqrt(eps),amplitudeFloorRatio*medianMag);
u = x./max(mag,floorMag);
z = u.^M;

% Down-weight deep fades while retaining a causal fixed-memory estimator.
weight = min(1,mag/max(medianMag,eps)).^2;
weighted = z.*weight;
cs = [complex(0); cumsum(weighted)];
cw = [0; cumsum(weight)];
phasor = complex(zeros(size(x)));
for k = 1:numel(x)
    first = max(1,k-windowSymbols+1);
    denom = cw(k+1)-cw(first);
    if denom > eps
        phasor(k) = (cs(k+1)-cs(first))/denom;
    elseif k > 1
        phasor(k) = phasor(k-1);
    else
        phasor(k) = 1;
    end
end

confidence = abs(phasor);
validPhase = confidence >= minConfidence & ...
    isfinite(real(phasor)) & isfinite(imag(phasor));

% Estimate a small initial M-domain residual frequency from adjacent
% reliable phasors.  Using phase differences avoids any absolute branch.
initLast = min(numel(x),initialFrequencySymbols);
pairValid = validPhase(1:max(0,initLast-1)) & ...
    validPhase(2:initLast);
if any(pairValid)
    initDiff = angle(phasor(2:initLast).*conj(phasor(1:initLast-1)));
    initialOmega = median(initDiff(pairValid));
else
    initialOmega = 0;
end
initialOmega = min(max(initialOmega,-maxRaisedFrequency), ...
    maxRaisedFrequency);

% Continuous-state second-order PLL in the Mth-power domain.  During a
% fade, the NCO advances with its last frequency but phase/frequency are not
% updated from noise.  When confidence returns, the wrapped detector error
% pulls the same state back; there is no per-island unwrap operation.
[alpha,beta] = localSecondOrderLoopGains(loopBandwidth,damping);
phaseM = zeros(size(x));
phaseError = NaN(size(x));
frequencyM = zeros(size(x));
firstValid = find(validPhase,1,'first');
if isempty(firstValid)
    phaseState = angle(phasor(1));
else
    phaseState = angle(phasor(firstValid)) - initialOmega*(firstValid-1);
end
omegaState = initialOmega;
for k = 1:numel(x)
    if k > 1
        phaseState = phaseState + omegaState;
    end
    if validPhase(k)
        err = angle(phasor(k)*exp(-1j*phaseState));
        phaseState = phaseState + alpha*err;
        omegaState = omegaState + beta*err;
        omegaState = min(max(omegaState,-maxRaisedFrequency), ...
            maxRaisedFrequency);
        phaseError(k) = err;
    end
    phaseM(k) = phaseState;
    frequencyM(k) = omegaState;
end

phaseTrack = phaseM/M;
anchorCount = min(numel(x),max(8,round(windowSymbols/2)));
anchor = median(phaseTrack(1:anchorCount));
phaseCorrection = phaseTrack-anchor;
yOut = x.*exp(-1j*phaseCorrection);

info = localEmptyInfo();
info.Applied = true;
info.Reason = 'causal Mth-power differential phase tracking';
info.PowerOrder = M;
info.WindowSymbols = windowSymbols;
info.AnchorPhase_deg = rad2deg(anchor);
info.FinalCorrection_deg = rad2deg(phaseCorrection(end));
info.CorrectionRMS_deg = rad2deg(sqrt(mean(phaseCorrection.^2)));
info.MedianConfidence = median(confidence);
info.MinConfidence = min(confidence);
info.ConfidenceThreshold = minConfidence;
info.HeldSymbols = nnz(~validPhase);
info.FadeWeightedSymbols = nnz(weight < 0.25);
info.LoopBandwidth = loopBandwidth;
info.InitialRaisedFrequencyRadPerSymbol = initialOmega;
info.FinalRaisedFrequencyRadPerSymbol = frequencyM(end);
validError = phaseError(isfinite(phaseError));
if isempty(validError)
    info.RaisedPhaseErrorRMS_deg = NaN;
else
    info.RaisedPhaseErrorRMS_deg = rad2deg(sqrt(mean(validError.^2)));
end

state = struct('FinalPhaseRad',phaseTrack(end), ...
    'FinalCorrectionRad',phaseCorrection(end),'PowerOrder',M, ...
    'LastPhasor',phasor(end), ...
    'FinalRaisedFrequencyRadPerSymbol',frequencyM(end));

if debugEnabled
    fprintf('\n[TM APSK Mth-power phase tracker]\n');
    fprintf('  M/window         : %d / %d symbols\n',M,windowSymbols);
    fprintf('  anchor/final     : %+.3f / %+.3f deg\n', ...
        info.AnchorPhase_deg,info.FinalCorrection_deg);
    fprintf('  confidence       : median=%.4f min=%.4f\n', ...
        info.MedianConfidence,info.MinConfidence);
    fprintf('  confidence hold  : %d/%d symbols (threshold %.3f)\n', ...
        info.HeldSymbols,numel(x),info.ConfidenceThreshold);
    fprintf('  raised PLL       : BW=%.4g init/final omega=%+.6g/%+.6g rad/sym\n', ...
        info.LoopBandwidth,info.InitialRaisedFrequencyRadPerSymbol, ...
        info.FinalRaisedFrequencyRadPerSymbol);
    fprintf('  fade weighted    : %d/%d symbols\n\n', ...
        info.FadeWeightedSymbols,numel(x));
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

function info = localEmptyInfo()
info = struct('Applied',false,'Reason','', ...
    'PowerOrder',NaN,'WindowSymbols',NaN, ...
    'AnchorPhase_deg',NaN,'FinalCorrection_deg',NaN, ...
    'CorrectionRMS_deg',NaN,'MedianConfidence',NaN, ...
    'MinConfidence',NaN,'ConfidenceThreshold',NaN, ...
    'HeldSymbols',0,'FadeWeightedSymbols',0, ...
    'LoopBandwidth',NaN, ...
    'InitialRaisedFrequencyRadPerSymbol',NaN, ...
    'FinalRaisedFrequencyRadPerSymbol',NaN, ...
    'RaisedPhaseErrorRMS_deg',NaN);
end

function [alpha,beta] = localSecondOrderLoopGains(loopBW,damping)
denom = 1 + 2*damping*loopBW + loopBW^2;
alpha = (4*damping*loopBW)/denom;
beta = (4*loopBW^2)/denom;
end
