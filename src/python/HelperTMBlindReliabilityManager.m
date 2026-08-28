function [ctrl,info] = HelperTMBlindReliabilityManager(x,options)
%HELPERTMBLINDRELIABILITYMANAGER Shared blind power-reliability state.
%
%   [CTRL,INFO] = HelperTMBlindReliabilityManager(X,OPTIONS)
%
% X is the matched-filter output before FastEnvelope.  This first version
% deliberately uses only relative window power; it does not inspect H,
% transmitted bits, pilots, ASM, decisions, or the selected FEC.  HOLD and
% RECOVER are therefore a common receiver observation rather than another
% modulation-specific decision gate.
%
% State codes in CTRL.StateCodeTrace are:
%   1 TRACK, 2 HOLD, 3 RECOVER.

% The manager does not modify X.  Consumers use the common masks to freeze
% their own adaptive state while continuing to produce holdover output.

% Important OPTIONS (defaults)
%   SamplesPerSymbol       2
%   WindowSymbols          32
%   AcquireSymbols         256
%   ReferenceTauSymbols    4096
%   FadeEnterDB            -12
%   FadeExitDB             -8
%   FadeEnterWindows       2
%   RecoverWindows         4
%   MaxInverseGainDB       18
%   Debug                  false


if nargin < 2 || isempty(options)
    options = struct();
end
x = complex(x(:));

ctrl = localEmptyControl(numel(x));
info = localEmptyInfo();
if isempty(x)
    info.Reason = 'empty input';
    return;
end
if any(~isfinite(real(x))) || any(~isfinite(imag(x)))
    error('HelperTMBlindReliabilityManager:InvalidInput', ...
        'Input contains NaN or Inf.');
end

sps = max(1,localNumber(options,'SamplesPerSymbol',2));
windowSymbols = max(4,round(localNumber(options,'WindowSymbols',32)));
windowSamples = max(4,round(windowSymbols*sps));
acquireSymbols = max(windowSymbols,round(localNumber( ...
    options,'AcquireSymbols',256)));
acquireWindows = max(1,ceil(acquireSymbols/windowSymbols));
referenceTauSymbols = max(windowSymbols,localNumber( ...
    options,'ReferenceTauSymbols',4096));
fadeEnterDB = localNumber(options,'FadeEnterDB',-12);
fadeExitDB = localNumber(options,'FadeExitDB',-8);
fadeEnterWindows = max(1,round(localNumber( ...
    options,'FadeEnterWindows',2)));
recoverWindowsRequired = max(1,round(localNumber( ...
    options,'RecoverWindows',4)));
maxInverseGainDB = localNumber(options,'MaxInverseGainDB',18);
debugEnabled = localLogical(options,'Debug',false);

if ~isfinite(fadeEnterDB) || ~isfinite(fadeExitDB) || ...
        fadeExitDB <= fadeEnterDB
    error('HelperTMBlindReliabilityManager:InvalidHysteresis', ...
        'FadeExitDB must be finite and greater than FadeEnterDB.');
end
if ~isfinite(maxInverseGainDB) || maxInverseGainDB < 0
    error('HelperTMBlindReliabilityManager:InvalidGainLimit', ...
        'MaxInverseGainDB must be a finite nonnegative scalar.');
end

n = numel(x);
nWindows = ceil(n/windowSamples);
windowPower = zeros(nWindows,1);
windowFirst = zeros(nWindows,1);
windowLast = zeros(nWindows,1);
for w = 1:nWindows
    first = (w-1)*windowSamples+1;
    last = min(n,w*windowSamples);
    windowFirst(w) = first;
    windowLast(w) = last;
    p = abs(x(first:last)).^2;
    windowPower(w) = mean(p);
end
windowPower = max(windowPower,eps);

% A short upper-quartile acquisition estimate is less sensitive than the
% first sample/window to constellation activity or a fade at t=0.  It is a
% bounded-buffer operation and does not require knowledge of H.
nAcquire = min(nWindows,acquireWindows);
initialSet = sort(windowPower(1:nAcquire));
referencePower = initialSet(max(1,ceil(0.75*numel(initialSet))));
referencePower = max(referencePower,eps);
initialReferencePower = referencePower;
referenceAlpha = 1-exp(-windowSymbols/referenceTauSymbols);

state = uint8(1); % TRACK
badWindows = 0;
goodWindows = 0;
holdEvents = 0;
recoverEvents = 0;
holdWindowMask = false(nWindows,1);
relativePowerDB = zeros(nWindows,1);
stateWindowTrace = ones(nWindows,1,'uint8');

for w = 1:nWindows
    relativePowerDB(w) = 10*log10(windowPower(w)/max(referencePower,eps));

    % During the bounded acquisition prefix, collect a stable reference and
    % do not declare a fade from an incompletely initialized detector.
    if w <= nAcquire
        stateWindowTrace(w) = uint8(1);
        continue;
    end

    switch state
        case 1 % TRACK
            if relativePowerDB(w) <= fadeEnterDB
                badWindows = badWindows+1;
            else
                badWindows = 0;
            end
            if badWindows >= fadeEnterWindows
                state = uint8(2);
                holdEvents = holdEvents+1;
                goodWindows = 0;
                % Processing is block/offline here, so include the complete
                % confirming run rather than allowing its first low-power
                % window to update downstream adaptive states.
                firstHold = max(1,w-fadeEnterWindows+1);
                holdWindowMask(firstHold:w) = true;
                stateWindowTrace(firstHold:w) = uint8(2);
            elseif relativePowerDB(w) >= fadeExitDB
                % The slow normal-power reference is allowed to move only
                % during reliable TRACK operation.  It is frozen in a fade.
                referencePower = (1-referenceAlpha)*referencePower + ...
                    referenceAlpha*windowPower(w);
            end

        case 2 % HOLD
            holdWindowMask(w) = true;
            if relativePowerDB(w) >= fadeExitDB
                state = uint8(3);
                goodWindows = 1;
            else
                goodWindows = 0;
            end

        case 3 % RECOVER; adaptive consumers remain frozen
            holdWindowMask(w) = true;
            if relativePowerDB(w) <= fadeEnterDB
                state = uint8(2);
                goodWindows = 0;
            elseif relativePowerDB(w) >= fadeExitDB
                goodWindows = goodWindows+1;
                if goodWindows >= recoverWindowsRequired
                    state = uint8(1);
                    recoverEvents = recoverEvents+1;
                    badWindows = 0;
                    goodWindows = 0;
                end
            else
                goodWindows = 0;
            end
    end

    if state ~= 1
        holdWindowMask(w) = true;
    end
    stateWindowTrace(w) = state;
end

holdMask = false(n,1);
stateCodeTrace = ones(n,1,'uint8');
relativePowerSampleDB = zeros(n,1);
for w = 1:nWindows
    idx = windowFirst(w):windowLast(w);
    holdMask(idx) = holdWindowMask(w);
    stateCodeTrace(idx) = stateWindowTrace(w);
    relativePowerSampleDB(idx) = relativePowerDB(w);
end

ctrl.Applied = true;
ctrl.State = localStateName(state);
ctrl.StateCodeTrace = stateCodeTrace;
ctrl.HoldMask = holdMask;
ctrl.AllowEnvelopeUpdate = ~holdMask;
ctrl.AllowGainUpdate = ~holdMask;
ctrl.AllowEqualizerUpdate = ~holdMask;
ctrl.RelativePowerDB = relativePowerSampleDB;
ctrl.MaxInverseGainDB = maxInverseGainDB;

info.Applied = true;
info.Reason = 'blind pre-normalization relative-power TRACK/HOLD/RECOVER';
info.FinalState = ctrl.State;
info.SamplesPerSymbol = sps;
info.WindowSymbols = windowSamples/sps;
info.WindowSamples = windowSamples;
info.NumWindows = nWindows;
info.AcquireWindows = nAcquire;
info.ReferenceTauSymbols = referenceTauSymbols;
info.ReferencePowerInitial = initialReferencePower;
info.ReferencePowerFinal = referencePower;
info.FadeEnterDB = fadeEnterDB;
info.FadeExitDB = fadeExitDB;
info.FadeEnterWindows = fadeEnterWindows;
info.RecoverWindows = recoverWindowsRequired;
info.HoldWindows = nnz(holdWindowMask);
info.HoldSamples = nnz(holdMask);
info.HoldFraction = mean(holdMask);
info.HoldEvents = holdEvents;
info.RecoverEvents = recoverEvents;
info.MinRelativePowerDB = min(relativePowerDB);
info.MedianRelativePowerDB = median(relativePowerDB);
info.MaxRelativePowerDB = max(relativePowerDB);
info.MaxInverseGainDB = maxInverseGainDB;

if debugEnabled
    fprintf('\n[TM blind reliability manager]\n');
    fprintf('  detector         : pre-envelope power, %.1f symbols/window\n', ...
        info.WindowSymbols);
    fprintf('  thresholds       : enter=%+.1f dB x%d, exit=%+.1f dB x%d\n', ...
        fadeEnterDB,fadeEnterWindows,fadeExitDB,recoverWindowsRequired);
    fprintf('  power ratio      : min/median/max=%+.2f/%+.2f/%+.2f dB\n', ...
        info.MinRelativePowerDB,info.MedianRelativePowerDB, ...
        info.MaxRelativePowerDB);
    fprintf('  HOLD             : %d/%d windows, %d/%d samples (%.2f%%)\n', ...
        info.HoldWindows,info.NumWindows,info.HoldSamples,n, ...
        100*info.HoldFraction);
    fprintf('  transitions      : enter/recover=%d/%d, final=%s\n', ...
        info.HoldEvents,info.RecoverEvents,info.FinalState);
    fprintf('  inverse gain cap : %+.1f dB\n\n',maxInverseGainDB);
end
end

function name = localStateName(code)
switch uint8(code)
    case 1
        name = 'TRACK';
    case 2
        name = 'HOLD';
    otherwise
        name = 'RECOVER';
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

function ctrl = localEmptyControl(n)
ctrl = struct('Applied',false,'State','TRACK', ...
    'StateCodeTrace',ones(n,1,'uint8'),'HoldMask',false(n,1), ...
    'AllowEnvelopeUpdate',true(n,1),'AllowGainUpdate',true(n,1), ...
    'AllowEqualizerUpdate',true(n,1),'RelativePowerDB',zeros(n,1), ...
    'MaxInverseGainDB',NaN);
end

function info = localEmptyInfo()
info = struct('Applied',false,'Reason','disabled','FinalState','TRACK', ...
    'SamplesPerSymbol',NaN,'WindowSymbols',NaN,'WindowSamples',NaN, ...
    'NumWindows',0,'AcquireWindows',0,'ReferenceTauSymbols',NaN, ...
    'ReferencePowerInitial',NaN,'ReferencePowerFinal',NaN, ...
    'FadeEnterDB',NaN,'FadeExitDB',NaN,'FadeEnterWindows',NaN, ...
    'RecoverWindows',NaN,'HoldWindows',0,'HoldSamples',0, ...
    'HoldFraction',0,'HoldEvents',0,'RecoverEvents',0, ...
    'MinRelativePowerDB',NaN,'MedianRelativePowerDB',NaN, ...
    'MaxRelativePowerDB',NaN,'MaxInverseGainDB',NaN);
end
