function [yEq, info] = HelperTMFractionallySpacedDualModeEqualizer(x, refConst, options)
%HELPERTMFRACTIONALLYSPACEDDUALMODEEQUALIZER Experimental 2-sps CMA/DD FSE.
%   One 2-sps tap vector is acquired by the same comm.LinearEqualizer CMA
%   implementation used by the validated baseline. The final CMA weights
%   then continue in a carrier-aided, gated DD-NLMS loop. The internal carrier
%   reference is used for decisions only: output retains the continuous phase
%   seen by the downstream CarrierSynchronizer. No symbol-rate FIR is appended.
%
%   This is an isolated A/B path for BPSK/QPSK/8PSK. The legacy
%   HelperTMFractionallySpacedCMAEqualizer remains unchanged and is still
%   selected by adaptiveEqualizerSamplingMode="2sps".

x = complex(x(:));
refConst = complex(refConst(:));
info = localEmptyInfo();

if isempty(x)
    yEq = x;
    info.Reason = 'empty input';
    return;
end
if isempty(refConst) || any(~isfinite(refConst))
    yEq = x;
    info.Reason = 'empty or invalid reference constellation';
    return;
end

modulation = upper(strtrim(string(localText(options,'modType',''))));
if ~any(modulation == ["BPSK","QPSK","8PSK"])
    error('HelperTMFractionallySpacedDualModeEqualizer:UnsupportedModulation', ...
        ['The experimental dual-mode 2-sps FSE supports only ', ...
         'BPSK/QPSK/8PSK; requested modulation is %s.'],char(modulation));
end

inputSPS = round(localNumber(options, ...
    'adaptiveFractionalEqualizerInputSamplesPerSymbol',2));
if inputSPS ~= 2
    error('HelperTMFractionallySpacedDualModeEqualizer:InvalidInputSPS', ...
        'adaptiveFractionalEqualizerInputSamplesPerSymbol must be 2.');
end
nInput = floor(numel(x)/inputSPS)*inputSPS;
xWork = x(1:nInput);
nSymbols = nInput/inputSPS;

nTaps = max(inputSPS,round(localNumber(options, ...
    'adaptiveFractionalEqualizerTaps',49)));
if mod(nTaps,2) == 0
    nTaps = nTaps+1;
end
referenceTap = round(localNumber(options, ...
    'adaptiveFractionalEqualizerReferenceTap',ceil(nTaps/2)));
referenceTap = min(nTaps,max(1,referenceTap));
weightUpdatePeriod = max(1,round(localNumber(options, ...
    'adaptiveFractionalEqualizerWeightUpdatePeriod',1)));

muCMA = localNumber(options,'adaptiveFractionalEqualizerStep',2e-4);
muDD = localNumber(options,'adaptiveFractionalDualDDStep',0.03);
if ~localPositiveScalar(muCMA) || ~localPositiveScalar(muDD) || muDD > 2
    error('HelperTMFractionallySpacedDualModeEqualizer:InvalidStepSize', ...
        ['CMA step must be positive and finite; DD-NLMS step must be ', ...
         'positive, finite, and no greater than 2.']);
end
if nSymbols < max(256,nTaps)
    yEq = xWork(1:inputSPS:end);
    info.Reason = 'input shorter than the dual-mode acquisition span';
    return;
end

referencePower = mean(abs(refConst).^2);
inputPower = mean(abs(xWork).^2);
if ~isfinite(inputPower) || inputPower <= realmin('double')
    error('HelperTMFractionallySpacedDualModeEqualizer:NoUsableInputPower', ...
        'The 2-sps FSE input has no finite nonzero power.');
end
xWork = xWork*sqrt(referencePower/inputPower);

% Only acquisition length and DD step are exposed for controlled A/B tests.
% Decision and phase-loop constants belong to this helper, not the frontend.
defaultAcquisition = max(32768,256*nTaps);
requestedAcquisition = round(localNumber(options, ...
    'adaptiveFractionalDualCMAAcquisitionSymbols',defaultAcquisition));
if ~localPositiveScalar(requestedAcquisition)
    error('HelperTMFractionallySpacedDualModeEqualizer:InvalidAcquisitionLength', ...
        'adaptiveFractionalDualCMAAcquisitionSymbols must be positive and finite.');
end
minimumDD = min(2048,max(256,floor(nSymbols/4)));
cmaSymbols = max(nTaps,requestedAcquisition);
if nSymbols < cmaSymbols+minimumDD
    [yEq,baselineInfo] = HelperTMFractionallySpacedCMAEqualizer(x,refConst,options);
    info = localFromBaseline(baselineInfo);
    info.Reason = 'record too short for requested CMA acquisition; full-record CMA used';
    return;
end
phaseStep = 0.08;
minimumDistance = localMinimumDistance(refConst);
% A tight radius censors radial errors that DD must remove. Reject gross
% outliers while allowing useful ISI gradients to update the existing taps.
decisionGate = 0.75*minimumDistance;
minimumCMAConfidence = 0.90;
epsilon = 1e-8;
maxTapNorm = 8;

% Stage 1 deliberately uses the exact baseline CMA object. This prevents a
% new CMA implementation from becoming a hidden second variable in the A/B.
cma = comm.LinearEqualizer( ...
    'Algorithm','CMA', ...
    'NumTaps',nTaps, ...
    'StepSize',muCMA, ...
    'Constellation',refConst.', ...
    'ReferenceTap',referenceTap, ...
    'InputSamplesPerSymbol',inputSPS, ...
    'WeightUpdatePeriod',weightUpdatePeriod, ...
    'ErrorOutputPort',true, ...
    'TapWeightsOutputPort',true);
[firstOutput,firstError,w] = cma(xWork(1:inputSPS*cmaSymbols));
yCMA = complex(zeros(nSymbols,1));
cmaError = complex(NaN(nSymbols,1));
yCMA(1:cmaSymbols) = firstOutput(:);
cmaError(1:cmaSymbols) = firstError(:);
w = complex(w(:));

phaseOrder = localPhaseOrder(modulation);
symbolRateHz = localNumber(options,'symbolRate',NaN);
if ~localPositiveScalar(symbolRateHz)
    error('HelperTMFractionallySpacedDualModeEqualizer:InvalidSymbolRate', ...
        'symbolRate is required for the DD carrier reference.');
end
captureHz = abs(localNumber(options,'carrierCaptureRangeHz',2e6));
% Estimate residual frequency on acquired CMA symbols, without changing the
% output. A static phase average would decorrelate even at a modest Doppler
% (for example -18.8 kHz at 30 Msym/s) and reject a usable CMA solution.
while true
    carrierStart = min(cmaSymbols-1,max(2000,16*nTaps));
    [~,carrierFrequencyHz,carrierAcquireInfo] = ...
        robustPSKCoarseFrequencyCompensator( ...
        yCMA(carrierStart+1:cmaSymbols),symbolRateHz,char(modulation),captureHz);
    phaseIncrement = 2*pi*carrierFrequencyHz/symbolRateHz;
    tailCount = min(cmaSymbols,max(512,16*nTaps));
    tail = yCMA(cmaSymbols-tailCount+1:cmaSymbols);
    tail = tail.*exp(-1j*phaseIncrement*(-tailCount+1:0).');
    [phaseOffset,phaseCoherence] = localPSKPhaseOffset(tail,refConst,phaseOrder);
    tailAligned = tail*exp(-1j*phaseOffset);
    tailDistance = localNearest(tailAligned,refConst);
    % This is an observable gate-pass fraction, not a calibrated probability
    % of correct decisions or proof that the phase branch is correct.
    cmaConfidence = mean(tailDistance <= decisionGate);
    cmaStructureMSE = mean(tailDistance.^2);
    cmaQualified = isfinite(phaseOffset) && isfinite(phaseCoherence) && ...
        phaseCoherence >= 0.05 && cmaConfidence >= minimumCMAConfidence && ...
        carrierAcquireInfo.Accepted;
    if cmaQualified
        break;
    end
    % A minimum acquisition duration is not a declaration of convergence.
    % Keep the same CMA object learning until the one forward DD transition.
    nextCMASymbols = min(cmaSymbols+8192,nSymbols-minimumDD);
    if nextCMASymbols <= cmaSymbols
        break;
    end
    [nextOutput,nextError,w] = cma( ...
        xWork(inputSPS*cmaSymbols+1:inputSPS*nextCMASymbols));
    yCMA(cmaSymbols+1:nextCMASymbols) = nextOutput(:);
    cmaError(cmaSymbols+1:nextCMASymbols) = nextError(:);
    w = complex(w(:));
    cmaSymbols = nextCMASymbols;
end

if ~cmaQualified
    % A failed blind acquisition must never poison the validated path. Fall
    % back to unchanged full-record CMA instead of attempting DD.
    [yEq,baselineInfo] = HelperTMFractionallySpacedCMAEqualizer( ...
        x,refConst,options);
    info = localFromBaseline(baselineInfo);
    info.CMAAcquisitionSymbols = cmaSymbols;
    info.CMAStructureMSE = cmaStructureMSE;
    info.CMAConfidenceRate = cmaConfidence;
    info.CMAPhaseCoherence = phaseCoherence;
    info.CMAQualified = false;
    info.CarrierFrequency_Hz = carrierFrequencyHz;
    info.CarrierFrequencyAccepted = carrierAcquireInfo.Accepted;
    info.Reason = sprintf([ ...
        'dual switch rejected; unchanged full-record CMA used ', ...
        '(confidence %.1f%%/%.1f%%, coherence %.3f)'], ...
        100*cmaConfidence,100*minimumCMAConfidence,phaseCoherence);
    return;
end

% Keep the original CMA tap coordinates and output phase. Changing only the
% DD portion to a derotated stream introduces a phase/slope discontinuity at
% the switch and disturbs the downstream carrier loop.
yEq = complex(zeros(nSymbols,1));
yEq(1:cmaSymbols) = yCMA(1:cmaSymbols);
ddError = NaN(nSymbols,1);
carrierError = NaN(nSymbols,1);
accepted = false(nSymbols,1);
rejected = false(nSymbols,1);
rejectedTapUpdates = 0;
phaseState = phaseOffset;

% Instrumentation only: no TX reference enters this helper. Keep window
% aggregates and bounded sample crops, not another full-record state trace.
diagnosticEnabled = isfield(options,'FSEDiagnostics') && ...
    isstruct(options.FSEDiagnostics);
if diagnosticEnabled
    diagnosticCapture = HelperTMFSEDiagnosticCapture(yEq,options);
    diagnosticIndices = diagnosticCapture.SymbolIndex;
    diagnosticCapture.CorrectedForDecision = complex(NaN(size(diagnosticIndices)));
    diagnosticCapture.Decision = complex(NaN(size(diagnosticIndices)));
    diagnosticCapture.GatePassed = false(size(diagnosticIndices));
    diagnosticCapture.UpdateApplied = false(size(diagnosticIndices));
    diagnosticCapture.FeedbackIdentityResidual = NaN(size(diagnosticIndices));
    diagnosticPosition = 1;
    diagnosticWindow = 2048;
    diagnosticNumWindows = ceil(nSymbols/diagnosticWindow);
    diagnosticSums = zeros(diagnosticNumWindows,8);
    diagnosticTapNorm = NaN(diagnosticNumWindows,1);
    diagnosticTapChange = NaN(diagnosticNumWindows,1);
    diagnosticPhaseJump = NaN(diagnosticNumWindows,1);
    diagnosticPreviousBin = 0;
end

% comm.LinearEqualizer's 2-sps tap ordering is pair-wise:
% [x(2k-1),x(2k),x(2k-3),x(2k-2),...]. Reuse that exact ordering so the
% exported CMA weights continue in DD without a hidden permutation.
tapNumber = (0:nTaps-1).';
sampleOffsets = -2*floor(tapNumber/2)-1+mod(tapNumber,2);
for k = cmaSymbols+1:nSymbols
    if diagnosticEnabled
        diagnosticBin = floor((k-1)/diagnosticWindow)+1;
        if diagnosticBin ~= diagnosticPreviousBin
            diagnosticWindowWeights = w;
            diagnosticPreviousBin = diagnosticBin;
            diagnosticPhaseJump(diagnosticBin) = 0;
        end
        diagnosticOldPhase = phaseState;
        diagnosticUpdated = false;
        diagnosticFeedbackResidual = NaN;
        while diagnosticPosition <= numel(diagnosticIndices) && ...
                diagnosticIndices(diagnosticPosition) < k
            diagnosticPosition = diagnosticPosition+1;
        end
        diagnosticKeep = diagnosticPosition <= numel(diagnosticIndices) && ...
            diagnosticIndices(diagnosticPosition) == k;
    end
    indices = inputSPS*k+sampleOffsets;
    xv = xWork(indices);
    y = w'*xv;
    phaseState = localWrapPhase(phaseState+phaseIncrement);
    z = y*exp(-1j*phaseState);
    [distance,dHat] = localNearest(z,refConst);
    errDecision = dHat-z;
    ddError(k) = abs(errDecision)^2;
    if distance <= decisionGate
        phaseError = angle(z*conj(dHat));
        carrierError(k) = phaseError;
        % Use the same phase for the sample, decision, and tap gradient.
        % Update the carrier reference only after constructing this gradient.
        desiredAtTapOutput = dHat*exp(1j*phaseState);
        errAtTapOutput = desiredAtTapOutput-y;
        phaseState = localWrapPhase(phaseState+phaseStep*phaseError);
        if mod(k-cmaSymbols-1,weightUpdatePeriod) == 0
            powerX = real(xv'*xv)+epsilon;
            candidate = w+(muDD/powerX)*xv*conj(errAtTapOutput);
            if all(isfinite(candidate)) && norm(candidate) <= maxTapNorm
                if diagnosticEnabled
                    diagnosticUpdated = true;
                    if diagnosticKeep
                        % Delta output predicted using the SAME x(k). A
                        % downstream CarrierSynchronizer is not in this loop.
                        diagnosticFeedbackResidual = abs((candidate-w)'*xv - ...
                            muDD*errAtTapOutput*real(xv'*xv)/powerX);
                    end
                end
                w = candidate;
                accepted(k) = true;
            else
                rejected(k) = true;
                rejectedTapUpdates = rejectedTapUpdates+1;
            end
        else
            accepted(k) = true;
        end
    else
        % Keep the carrier prediction advancing; freeze decision-driven
        % corrections and tap adaptation on gross outliers.
        rejected(k) = true;
    end
    yEq(k) = y;
    if diagnosticEnabled
        diagnosticAngle = abs(angle(z*conj(dHat)));
        diagnosticSums(diagnosticBin,:) = diagnosticSums(diagnosticBin,:) + ...
            [1, distance, pi/phaseOrder-diagnosticAngle, ...
             double(distance<=decisionGate), double(diagnosticUpdated), ...
             diagnosticAngle, abs(errDecision)^2, double(accepted(k))];
        diagnosticPhaseJump(diagnosticBin) = max( ...
            diagnosticPhaseJump(diagnosticBin), ...
            abs(localWrapPhase(phaseState-diagnosticOldPhase))*180/pi);
        if diagnosticKeep
            diagnosticCapture.CorrectedForDecision(diagnosticPosition) = z;
            diagnosticCapture.Decision(diagnosticPosition) = dHat;
            diagnosticCapture.GatePassed(diagnosticPosition) = distance<=decisionGate;
            diagnosticCapture.UpdateApplied(diagnosticPosition) = diagnosticUpdated;
            diagnosticCapture.FeedbackIdentityResidual(diagnosticPosition) = ...
                diagnosticFeedbackResidual;
        end
        if mod(k,diagnosticWindow)==0 || k==nSymbols
            diagnosticTapNorm(diagnosticBin) = norm(w);
            diagnosticTapChange(diagnosticBin) = norm(w-diagnosticWindowWeights);
        end
    end
end

if any(~isfinite(real(yEq))) || any(~isfinite(imag(yEq)))
    error('HelperTMFractionallySpacedDualModeEqualizer:NonfiniteOutput', ...
        'The dual-mode FSE produced a nonfinite output.');
end
outputPower = mean(abs(yEq).^2);
if isfinite(outputPower) && outputPower > realmin('double')
    yEq = yEq*sqrt(referencePower/outputPower);
end

decisionCount = nSymbols-cmaSymbols;
acceptedCount = nnz(accepted);
rejectedCount = nnz(rejected);
acceptanceRate = acceptedCount/max(decisionCount,1);
metricWarmup = min(cmaSymbols-1,max(0,round(localNumber(options, ...
    'adaptiveFractionalEqualizerMetricWarmupSymbols',2000))));

info.Applied = true;
info.Mode = 'fractionally-spaced-2sps-cma-dd-nlms';
info.InputSamplesPerSymbol = inputSPS;
info.NumTaps = nTaps;
info.ReferenceTap = referenceTap;
info.StepSize = muCMA;
info.DDStep = muDD;
info.WeightUpdatePeriod = weightUpdatePeriod;
info.InputSamples = nInput;
info.OutputSymbols = nSymbols;
info.InputPower = inputPower;
info.OutputPower = mean(abs(yEq).^2);
info.ErrorMSE = localFiniteMean(abs(cmaError(metricWarmup+1:cmaSymbols)).^2);
info.CMAErrorMSE = info.ErrorMSE;
info.DDMSE = localFiniteMean(ddError);
info.CMAAcquisitionSymbols = cmaSymbols;
info.CMAStructureMSE = cmaStructureMSE;
info.CMAConfidenceRate = cmaConfidence;
info.CMAPhaseCoherence = phaseCoherence;
info.CMAQualified = true;
info.SwitchApplied = true;
info.SwitchSymbol = cmaSymbols;
info.PhaseRotation_deg = 0;
info.CarrierPhaseStep = phaseStep;
info.CarrierFrequency_Hz = carrierFrequencyHz;
info.CarrierFrequencyAccepted = carrierAcquireInfo.Accepted;
info.CarrierInitialPhase_deg = phaseOffset*180/pi;
info.CarrierMeanAbsError_deg = localFiniteMean(abs(carrierError))*180/pi;
info.DecisionGate = decisionGate;
info.DecisionCount = decisionCount;
info.AcceptedDecisions = acceptedCount;
info.RejectedDecisions = rejectedCount;
info.AcceptanceRate = acceptanceRate;
info.FinalTapNorm = norm(w);
info.RejectedTapUpdates = rejectedTapUpdates;
info.Converged = isfinite(info.DDMSE) && acceptanceRate >= 0.50;
info.Reason = ['same 2-sps taps: baseline CMA acquisition -> ', ...
    'phase-aided gated DD-NLMS tracking'];
if diagnosticEnabled
    diagnosticCapture.Samples = yEq(diagnosticIndices);
    denom = diagnosticSums(:,1);
    denom(denom==0) = NaN;
    starts = (0:diagnosticNumWindows-1).'*diagnosticWindow+1;
    ends = min(starts+diagnosticWindow-1,nSymbols);
    cmaMSE = NaN(size(starts));
    for ib = 1:diagnosticNumWindows
        cmaMSE(ib) = localFiniteMean(abs(cmaError( ...
            starts(ib):min(ends(ib),cmaSymbols))).^2);
    end
    info.Diagnostics = struct();
    info.Diagnostics.WindowSymbols = diagnosticWindow;
    info.Diagnostics.Trace = table(starts,ends,cmaMSE, ...
        diagnosticSums(:,7)./denom,100*diagnosticSums(:,4)./denom, ...
        100*diagnosticSums(:,5)./denom,diagnosticSums(:,2)./denom, ...
        diagnosticSums(:,3)./denom*180/pi,diagnosticTapNorm, ...
        diagnosticTapChange,diagnosticSums(:,6)./denom*180/pi, ...
        diagnosticPhaseJump, ...
        'VariableNames',{'SymbolStart','SymbolEnd','CMAMSE','DDMSE', ...
        'DecisionGatePassPct','DDUpdatePct','MeanDecisionDistance', ...
        'MeanAngularMargin_deg','TapNorm','TapChangeNorm', ...
        'MeanAbsNearestPhaseError_deg','CarrierPhaseJump_deg'});
    info.Diagnostics.Samples = diagnosticCapture;
    info.Diagnostics.Meaning = ['Gate rates are not decision correctness; ', ...
        'TX comparisons must be attached OFFLINE after receiver completion.'];
end
end

function info = localFromBaseline(baseline)
info = localEmptyInfo();
names = fieldnames(baseline);
for k = 1:numel(names)
    if isfield(info,names{k})
        info.(names{k}) = baseline.(names{k});
    end
end
info.Mode = char(baseline.Mode);
end

function [distance,dHat] = localNearest(y,refConst)
[distance,index] = min(abs(y-refConst.'),[],2);
dHat = refConst(index);
end

function [phaseOffset,coherence] = localPSKPhaseOffset(y,refConst,order)
y = y(:);
usable = isfinite(real(y)) & isfinite(imag(y)) & abs(y) > 1e-8;
if ~any(usable)
    phaseOffset = NaN;
    coherence = 0;
    return;
end
unitY = y(usable)./abs(y(usable));
unitRef = refConst./max(abs(refConst),eps);
observed = mean(unitY.^order);
reference = mean(unitRef.^order);
coherence = abs(observed);
if abs(reference) <= eps || abs(observed) <= eps
    phaseOffset = NaN;
else
    phaseOffset = angle(observed/reference)/order;
end
end

function order = localPhaseOrder(modulation)
switch char(modulation)
    case 'BPSK'
        order = 2;
    case '8PSK'
        order = 8;
    otherwise
        order = 4;
end
end

function distance = localMinimumDistance(refConst)
pairDistance = abs(refConst-refConst.');
pairDistance(pairDistance <= 1e-12) = Inf;
distance = min(pairDistance(:));
if ~isfinite(distance)
    distance = 1;
end
end

function phase = localWrapPhase(phase)
phase = atan2(sin(phase),cos(phase));
end

function value = localFiniteMean(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = mean(x);
end
end

function tf = localPositiveScalar(value)
tf = isscalar(value) && isfinite(value) && value > 0;
end

function value = localNumber(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    candidate = double(s.(name));
    if isscalar(candidate)
        value = candidate;
    end
end
end

function value = localText(s,name,defaultValue)
value = char(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    candidate = string(s.(name));
    if isscalar(candidate)
        value = char(candidate);
    end
end
end

function info = localEmptyInfo()
info = struct( ...
    'Applied',false,'Mode','off','InputSamplesPerSymbol',2, ...
    'NumTaps',0,'ReferenceTap',0,'StepSize',NaN,'DDStep',NaN, ...
    'WeightUpdatePeriod',0,'InputSamples',0,'OutputSymbols',0, ...
    'InputPower',NaN,'OutputPower',NaN,'ErrorMSE',NaN, ...
    'CMAErrorMSE',NaN,'DDMSE',NaN,'CMAAcquisitionSymbols',0, ...
    'CMAStructureMSE',NaN,'CMAConfidenceRate',NaN, ...
    'CMAPhaseCoherence',NaN,'CMAQualified',false, ...
    'SwitchApplied',false,'SwitchSymbol',0,'PhaseRotation_deg',NaN, ...
    'CarrierPhaseStep',NaN,'CarrierMeanAbsError_deg',NaN, ...
    'CarrierFrequency_Hz',0,'CarrierFrequencyAccepted',false, ...
    'CarrierInitialPhase_deg',NaN, ...
    'DecisionGate',NaN,'DecisionCount',0,'AcceptedDecisions',0, ...
    'RejectedDecisions',0,'AcceptanceRate',NaN,'FinalTapNorm',NaN, ...
    'RejectedTapUpdates',0,'Converged',false,'Reason','disabled');
end
