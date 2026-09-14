function [yEq, info] = HelperTMDecisionFeedbackEqualizer(x, refConst, options)
%HELPERTMDECISIONFEEDBACKEQUALIZER Symbol-rate decision-directed NLMS DFE.
%   This helper is an optional refinement stage after the 2-sps blind CMA
%   FSE and carrier recovery.  It uses receiver decisions only: no true
%   transmitted symbols, H coefficients, BER feedback, or decoder output.

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

nForward = max(1,round(localNumber(options, ...
    'adaptiveFractionalPostForwardTaps',9)));
if nForward > 1 && mod(nForward,2) == 0
    nForward = nForward+1;
end
nFeedback = max(1,round(localNumber(options, ...
    'adaptiveFractionalPostFeedbackTaps',24)));
stepSize = localNumber(options,'adaptiveFractionalPostDDStep',5e-4);
if ~isscalar(stepSize) || ~isfinite(stepSize) || stepSize <= 0
    error('HelperTMDecisionFeedbackEqualizer:InvalidStepSize', ...
        'adaptiveFractionalPostDDStep must be a finite positive scalar.');
end
epsilon = max(1e-12,localNumber(options, ...
    'adaptiveFractionalPostEpsilon',1e-8));
maxWeightNorm = max(1,localNumber(options, ...
    'adaptiveFractionalPostMaxWeightNorm',8));
warmupSymbols = max(0,round(localNumber(options, ...
    'adaptiveFractionalPostWarmupSymbols',0)));

referencePower = mean(abs(refConst).^2);
inputPower = mean(abs(x).^2);
if ~isfinite(inputPower) || inputPower <= realmin('double')
    error('HelperTMDecisionFeedbackEqualizer:NoUsableInputPower', ...
        'The DD-DFE input has no finite nonzero power.');
end
xNorm = x*sqrt(referencePower/inputPower);
minimumDistance = localMinimumDistance(refConst);
decisionGate = localNumber(options, ...
    'adaptiveFractionalPostDecisionGate',0.45*minimumDistance);
if ~isscalar(decisionGate) || ~isfinite(decisionGate) || decisionGate <= 0
    error('HelperTMDecisionFeedbackEqualizer:InvalidDecisionGate', ...
        'adaptiveFractionalPostDecisionGate must be a finite positive scalar.');
end

forwardDelay = floor(nForward/2);
wForward = complex(zeros(nForward,1));
wForward(forwardDelay+1) = 1;
wFeedback = complex(zeros(nFeedback,1));
decisionHistory = complex(zeros(nFeedback,1));
yEq = xNorm;
decisionError = nan(numel(xNorm),1);
accepted = false(numel(xNorm),1);
rejected = false(numel(xNorm),1);
valid = (forwardDelay+1):(numel(xNorm)-forwardDelay);
if isempty(valid)
    info.Reason = 'input shorter than the forward-filter span';
    return;
end

for n = valid
    xv = xNorm(n+forwardDelay:-1:n-forwardDelay);
    y = wForward'*xv + wFeedback'*decisionHistory;
    yEq(n) = y;
    [distance,index] = min(abs(y-refConst));
    decision = refConst(index);
    errorDD = decision-y;
    decisionError(n) = abs(errorDD)^2;

    if n >= valid(1)+warmupSymbols && distance <= decisionGate
        regressor = [xv;decisionHistory];
        denominator = real(regressor'*regressor)+epsilon;
        candidateForward = wForward + ...
            (stepSize/denominator)*xv*conj(errorDD);
        candidateFeedback = wFeedback + ...
            (stepSize/denominator)*decisionHistory*conj(errorDD);
        if all(isfinite(candidateForward)) && ...
                all(isfinite(candidateFeedback)) && ...
                norm([candidateForward;candidateFeedback]) <= maxWeightNorm
            wForward = candidateForward;
            wFeedback = candidateFeedback;
            accepted(n) = true;
        else
            rejected(n) = true;
        end
    else
        rejected(n) = true;
    end
    decisionHistory = [decision;decisionHistory(1:end-1)];
end

inputStructureMSE = localStructureMSE(xNorm(valid),refConst);
outputStructureMSE = localStructureMSE(yEq(valid),refConst);
qualityImprovement = NaN;
if isfinite(inputStructureMSE) && inputStructureMSE > eps
    qualityImprovement = ...
        (inputStructureMSE-outputStructureMSE)/inputStructureMSE;
end
maxDegradation = max(0,localNumber(options, ...
    'adaptiveFractionalPostMaxMSEDegradation',0.05));
degradationMargin = max(0,localNumber(options, ...
    'adaptiveFractionalPostMSEDegradationMargin',1e-4*referencePower));
outputAccepted = ~(isfinite(inputStructureMSE) && ...
    isfinite(outputStructureMSE) && ...
    outputStructureMSE > inputStructureMSE*(1+maxDegradation) + ...
    degradationMargin);
if ~outputAccepted
    yEq = xNorm;
    reason = sprintf([ ...
        'DD-DFE constellation MSE degraded from %.4g to %.4g; ', ...
        'input retained'],inputStructureMSE,outputStructureMSE);
else
    reason = '2-sps CMA acquisition followed by symbol-rate DD-NLMS DFE';
end

finiteError = decisionError(isfinite(decisionError));
if isempty(finiteError)
    ddMSE = NaN;
else
    ddMSE = mean(finiteError);
end
decisionCount = numel(valid);
acceptanceRate = nnz(accepted)/max(decisionCount,1);

info.Applied = true;
info.Mode = 'dd-dfe';
info.ForwardTaps = nForward;
info.FeedbackTaps = nFeedback;
info.StepSize = stepSize;
info.DecisionGate = decisionGate;
info.DecisionCount = decisionCount;
info.AcceptedDecisions = nnz(accepted);
info.RejectedDecisions = nnz(rejected(valid));
info.AcceptanceRate = acceptanceRate;
info.DDMSE = ddMSE;
info.InputStructureMSE = inputStructureMSE;
info.OutputStructureMSE = outputStructureMSE;
info.QualityImprovement = qualityImprovement;
info.OutputAccepted = logical(outputAccepted);
info.Converged = outputAccepted && isfinite(ddMSE) && ...
    acceptanceRate >= localNumber(options, ...
    'adaptiveFractionalPostMinAcceptanceRate',0.50);
info.ForwardWeightNorm = norm(wForward);
info.FeedbackWeightNorm = norm(wFeedback);
info.Reason = reason;
end

function info = localEmptyInfo()
info = struct( ...
    'Applied',false,'Mode','off','ForwardTaps',0,'FeedbackTaps',0, ...
    'StepSize',NaN,'DecisionGate',NaN,'DecisionCount',0, ...
    'AcceptedDecisions',0,'RejectedDecisions',0,'AcceptanceRate',NaN, ...
    'DDMSE',NaN,'InputStructureMSE',NaN,'OutputStructureMSE',NaN, ...
    'QualityImprovement',NaN,'OutputAccepted',false,'Converged',false, ...
    'ForwardWeightNorm',NaN,'FeedbackWeightNorm',NaN,'Reason','disabled');
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

function d = localMinimumDistance(refConst)
d = Inf;
for k = 1:numel(refConst)
    other = abs(refConst(k)-refConst);
    other(k) = Inf;
    d = min(d,min(other));
end
if ~isfinite(d) || d <= 0
    d = 1;
end
end

function mse = localStructureMSE(symbols,refConst)
symbols = symbols(isfinite(symbols));
if isempty(symbols)
    mse = NaN;
    return;
end
distance2 = abs(symbols-refConst.').^2;
mse = mean(min(distance2,[],2));
end
