function [y, finalWeights, info] = HelperTMASMTrainingEqualizer( ...
        x, asmBits, modulation, framePeriodBits, options)
%HELPERTMASMTRAININGEQUALIZER ASM-training NLMS followed by gated DD-NLMS.
%
% This is a separate, explicitly selected equalizer mode.  It does not run
% CMA and it does not alter the existing blind-cma-lms implementation.
% Initial acquisition and every periodic refresh use the known transmitted
% ASM.  Payload symbols use nearest-constellation DD-NLMS.

if nargin < 5 || isempty(options)
    options = struct();
end
x = complex(x(:));
asmBits = int8(asmBits(:) ~= 0);
modulation = upper(string(modulation));
y = x;
finalWeights = complex(zeros(0,1));
info = localEmptyInfo();
info.Mode = 'asm-training-nlms';

if ~any(strcmp(modulation,["QPSK","16QAM"]))
    info.Reason = sprintf('mode supports QPSK/16QAM only, not %s',modulation);
    return;
end
if isempty(x) || isempty(asmBits)
    info.Reason = 'empty synchronized symbols or ASM bits';
    return;
end

[asmSymbols,bitsPerSymbol] = localMapBits(asmBits,modulation);
if mod(framePeriodBits,bitsPerSymbol) ~= 0
    info.Reason = sprintf('frame period %d bits is not symbol aligned', ...
        round(framePeriodBits));
    return;
end
periodSymbols = round(framePeriodBits/bitsPerSymbol);

[locations,locatorInfo] = HelperTMASMLocator( ...
    x,asmSymbols,periodSymbols,options);
info.ASMLocator = locatorInfo;
info.ASMCount = numel(locations);
info.ASMMedianScoreBefore = locatorInfo.MedianScore;
if isempty(locations)
    info.Reason = ['ASM locator failed: ',locatorInfo.Reason];
    return;
end

numTaps = max(1,round(localNumber(options,'asmTrainingEqualizerTaps',5)));
if mod(numTaps,2) == 0
    numTaps = numTaps+1;
end
delay = floor(numTaps/2);
trainingMu = min(max(localNumber(options,'asmTrainingNLMSMu',0.20),0),1);
ddMu = min(max(localNumber(options,'asmDDNLMSMu',0.03),0),0.5);
regularization = max(localNumber(options,'asmNLMSRegularization',1e-6),eps);
decisionGateScale = max(localNumber(options,'asmDDDecisionGate',0.45),0.05);
fadeThresholdDB = localNumber(options,'asmNLMSFadeThresholdDB',-15);
maxTapNorm = max(localNumber(options,'asmNLMSMaxTapNorm',8),1);
qualityGuard = localLogical(options,'asmTrainingQualityGuard',true);
minimumQualityImprovement = localNumber(options, ...
    'asmTrainingMinScoreImprovement',0.002);
minimumDistance = localMinimumDistance(localReference(modulation));
decisionGate = decisionGateScale*minimumDistance;

knownTraining = false(numel(x),1);
desiredTraining = complex(zeros(numel(x),1));
for kASM = 1:numel(locations)
    count = min(numel(asmSymbols),numel(x)-locations(kASM)+1);
    if count <= 0
        continue;
    end
    idx = locations(kASM)+(0:count-1);
    knownTraining(idx) = true;
    desiredTraining(idx) = asmSymbols(1:count);
end

% The scalar ASM gain supplies a reliable phase/amplitude initial value.
% With y=w^H*u, the centre coefficient is conj(1/gain).
initialGain = locatorInfo.ComplexGains(1);
weights = complex(zeros(numTaps,1));
if isfinite(real(initialGain)) && isfinite(imag(initialGain)) && ...
        abs(initialGain) > 1e-9
    weights(delay+1) = conj(1/initialGain);
else
    weights(delay+1) = 1;
end
lastGoodWeights = weights;

reference = localReference(modulation);
inputPower = median(abs(x).^2);
if ~isfinite(inputPower) || inputPower <= 0
    inputPower = mean(abs(x).^2);
end
inputPower = max(inputPower,1e-12);
fadePower = inputPower*10^(fadeThresholdDB/10);

padding = numTaps+2;
xp = [zeros(padding,1);x;zeros(padding,1)];
relative = delay:-1:-(numTaps-delay-1);
yCandidate = complex(zeros(size(x)));
trained = false;
trainingUpdates = 0;
ddAccepted = 0;
ddRejected = 0;
fadeHolds = 0;
trainingErrorPower = 0;
ddErrorPower = 0;

for k = 1:numel(x)
    xpIndex = padding+k+relative;
    u = xp(xpIndex(:));
    output = weights'*u;
    yCandidate(k) = output;

    if mean(abs(u).^2) < fadePower
        fadeHolds = fadeHolds+1;
        continue;
    end

    update = false;
    if knownTraining(k)
        desired = desiredTraining(k);
        mu = trainingMu;
        update = true;
        trained = true;
    elseif trained && ddMu > 0
        [desired,distance] = localNearest(output,reference);
        mu = ddMu;
        if isfinite(distance) && distance <= decisionGate
            update = true;
            ddAccepted = ddAccepted+1;
        else
            ddRejected = ddRejected+1;
        end
    end

    if update
        errorValue = desired-output;
        candidateWeights = weights + ...
            mu*u*conj(errorValue)/(real(u'*u)+regularization);
        if all(isfinite(real(candidateWeights))) && ...
                all(isfinite(imag(candidateWeights))) && ...
                norm(candidateWeights) <= maxTapNorm
            weights = candidateWeights;
            lastGoodWeights = weights;
            if knownTraining(k)
                trainingUpdates = trainingUpdates+1;
                trainingErrorPower = trainingErrorPower+abs(errorValue)^2;
            else
                ddErrorPower = ddErrorPower+abs(errorValue)^2;
            end
        else
            weights = lastGoodWeights;
        end
    end
end

% Keep the actual training -> DD state-machine output.  The centred FIR is
% implementable with a fixed delay buffer; no oracle channel coefficient or
% future training occurrence is applied retrospectively.
[~,afterLocator] = HelperTMASMLocator( ...
    yCandidate,asmSymbols,periodSymbols,options);
acceptedOutput = true;
rollbackReason = '';
if qualityGuard && isfinite(locatorInfo.MedianScore)
    if ~afterLocator.Applied || ~isfinite(afterLocator.MedianScore)
        acceptedOutput = false;
        rollbackReason = 'ASM locator failed after adaptive equalization';
    elseif afterLocator.MedianScore < ...
            locatorInfo.MedianScore+minimumQualityImprovement
        acceptedOutput = false;
        rollbackReason = sprintf( ...
            ['ASM median correlation did not improve by %.4f: ', ...
             '%.4f -> %.4f'], ...
            minimumQualityImprovement,locatorInfo.MedianScore, ...
            afterLocator.MedianScore);
    end
end
if acceptedOutput
    y = yCandidate;
else
    y = x;
end
finalWeights = weights;

info.Enabled = true;
info.NumTaps = numTaps;
info.CMADelay = delay;
info.CMASymbols = 0;
info.DDPasses = 1;
info.DDPassesRequested = 1;
info.CMAStep = NaN;
info.DDStep = ddMu;
info.CMAR2 = NaN;
info.BlindCostMode = 'asm-training';
info.DecisionGate = decisionGate;
info.AcceptedDecisions = ddAccepted;
info.RejectedDecisions = ddRejected;
info.DecisionCount = ddAccepted+ddRejected;
info.AcceptanceRate = ddAccepted/max(ddAccepted+ddRejected,1);
info.CMAMSE = trainingErrorPower/max(trainingUpdates,1);
info.DDMSE = ddErrorPower/max(ddAccepted,1);
info.FinalTapNorm = norm(weights);
info.EqualizerStructure = 'fir-asm-nlms';
info.OutputAccepted = acceptedOutput;
info.RollbackReason = rollbackReason;
info.Converged = trainingUpdates > 0 && acceptedOutput;
info.Reason = sprintf( ...
    'ASM training updates=%d, DD accepted=%d rejected=%d fadeHold=%d', ...
    trainingUpdates,ddAccepted,ddRejected,fadeHolds);
info.ASMPositions = locations;
info.ASMTrainingUpdates = trainingUpdates;
info.ASMMedianScoreAfter = afterLocator.MedianScore;
info.FadeHoldSamples = fadeHolds;
end

function [symbols,bitsPerSymbol] = localMapBits(bits,modulation)
    switch char(modulation)
        case 'QPSK'
            bitsPerSymbol = 2;
            if mod(numel(bits),2) ~= 0
                error('HelperTMASMTrainingEqualizer:ASMAlignment', ...
                    'QPSK ASM length must be divisible by 2.');
            end
            groups = reshape(double(bits),2,[]).';
            symbols = ((1-2*groups(:,1))+1j*(1-2*groups(:,2)))/sqrt(2);
        case '16QAM'
            bitsPerSymbol = 4;
            if mod(numel(bits),4) ~= 0
                error('HelperTMASMTrainingEqualizer:ASMAlignment', ...
                    '16QAM ASM length must be divisible by 4.');
            end
            symbols = qammod(double(bits),16,'InputType','bit', ...
                'UnitAveragePower',true);
        otherwise
            error('HelperTMASMTrainingEqualizer:UnsupportedModulation', ...
                'Only QPSK and 16QAM are supported.');
    end
    symbols = complex(symbols(:));
end

function reference = localReference(modulation)
    switch char(modulation)
        case 'QPSK'
            reference = [1+1j;1-1j;-1+1j;-1-1j]/sqrt(2);
        case '16QAM'
            reference = qammod((0:15).',16,'UnitAveragePower',true);
        otherwise
            reference = 1;
    end
end

function [decision,distance] = localNearest(value,reference)
    [distanceSquared,index] = min(abs(value-reference).^2);
    decision = reference(index);
    distance = sqrt(distanceSquared);
end

function distance = localMinimumDistance(reference)
    distance = inf;
    for k = 1:numel(reference)
        candidate = abs(reference(k)-reference([1:k-1,k+1:end]));
        if ~isempty(candidate)
            distance = min(distance,min(candidate));
        end
    end
    if ~isfinite(distance)
        distance = 1;
    end
end

function value = localNumber(s,name,fallback)
    value = fallback;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        candidate = double(s.(name));
        if isscalar(candidate) && isfinite(candidate)
            value = candidate;
        end
    end
end

function value = localLogical(s,name,fallback)
    value = fallback;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        value = logical(s.(name));
    end
end

function info = localEmptyInfo()
    info = struct( ...
        'Enabled',false,'Mode','off','NumTaps',0,'CMADelay',0, ...
        'CMASymbols',0,'DDPasses',0,'DDPassesRequested',0, ...
        'CMAStep',NaN,'DDStep',NaN,'CMAR2',NaN, ...
        'BlindCostMode','off','DecisionGate',NaN, ...
        'PhaseRotation_deg',NaN,'PhaseStructureScore',NaN, ...
        'CMASwitchMSE',NaN,'CMAConfidenceRate',NaN, ...
        'CMAQualified',false,'InputPower',NaN,'OutputPower',NaN, ...
        'AcceptedDecisions',0,'RejectedDecisions',0,'DecisionCount',0, ...
        'AcceptanceRate',NaN,'CMAMSE',NaN,'DDMSE',NaN, ...
        'FinalTapNorm',NaN,'EqualizerStructure','off', ...
        'SideTapEnergyRatio',NaN,'DDWindowSymbols',0, ...
        'DDMinWindowAcceptance',NaN,'DDWindowCount',0, ...
        'DDGoodWindows',0,'DDHoldWindows',0,'DDFadeHoldWindows',0, ...
        'FadeHoldDB',NaN,'DDHoldReason','', ...
        'InputStructureMSE',NaN,'OutputStructureMSE',NaN, ...
        'QualityImprovement',NaN,'OutputAccepted',false, ...
        'RollbackReason','','Converged',false,'Reason','disabled', ...
        'ASMLocator',struct(),'ASMCount',0, ...
        'ASMPositions',zeros(0,1),'ASMTrainingUpdates',0, ...
        'ASMMedianScoreBefore',NaN,'ASMMedianScoreAfter',NaN, ...
        'FadeHoldSamples',0);
end
