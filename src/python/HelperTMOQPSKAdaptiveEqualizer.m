function [y,info] = HelperTMOQPSKAdaptiveEqualizer(matched,sps,span,opt)
% OQPSK adapter: one complex T/2-spaced FIR, staggered real-rail CMA error.
% Input/output are MATCHED-FILTERED samples at the ORIGINAL sample rate.
% Unlike a QPSK slicer, only I at its eye center and Q half a symbol later
% contribute errors. The normalized complex tap update uses the same
% convention as HelperTMBlindCMAEqualizer: y=w'*u; w+=mu*u*conj(error)/power.
% This offline adapter uses a centered FIR (lookahead half its span), so it
% preserves sample indices and length. It is not a streaming receiver.
% No H, transmitted symbols, decoded bits, ASM or BER enter tap updates.
validateattributes(sps,{'numeric'},{'scalar','integer','>=',2});
assert(mod(sps,2)==0,'OQPSKEQ:OddSPS','OQPSK requires even SPS.');
matched = complex(matched(:));
assert(~isempty(matched) && all(isfinite(matched)), ...
    'OQPSKEQ:Input','OQPSK equalizer requires finite, nonempty input.');
taps = value(opt,'adaptiveEqualizerTaps',11);
validateattributes(taps,{'numeric'},{'scalar','integer','>=',3});
assert(mod(taps,2)==1,'OQPSKEQ:Taps','Use an odd tap count.');
mu = value(opt,'adaptiveEqualizerCMAStep',0.01);
validateattributes(mu,{'numeric'},{'scalar','finite','positive','<=',0.1});
maxNorm = value(opt,'adaptiveEqualizerMaxTapNorm',4);
validateattributes(maxNorm,{'numeric'},{'scalar','finite','>=',1});
[i0,q0,offset] = HelperTMOQPSKRailSamples(matched,sps,span);
assert(~isempty(i0),'OQPSKEQ:ShortInput','Not enough OQPSK rail samples.');
amplitude = sqrt(mean(i0.^2+q0.^2)/2+eps);
assert(isfinite(amplitude) && amplitude>0,'OQPSKEQ:InputPower', ...
    'OQPSK rail amplitude must be finite and positive.');
assert(any(abs(matched)>0),'OQPSKEQ:NoSignal', ...
    'Cannot adapt OQPSK equalizer on an all-zero waveform.');
x = matched/amplitude;
hop = sps/2;
half = (taps-1)/2;
padding = half*hop;
assert(numel(x)>2*(padding+span*sps)+sps,'OQPSKEQ:ShortInput', ...
    'Waveform is too short for the requested taps and filter transient.');
xp = [complex(zeros(padding,1));x;complex(zeros(padding,1))];
w = complex(zeros(taps,1));
w(half+1) = 1;
y = complex(zeros(size(x)));
relative = (half:-1:-half)'*hop;
updates = 0;
attempts = 0;
projectedUpdates = 0;
rejectedUpdates = 0;
firstConstrainedSample = NaN;
peakTapNorm = norm(w);
maxCandidateNorm = norm(w);
costSum = 0;
% Evaluate every output sample; update only at alternating rail eye centers.
% The regressor used in the update is exactly the one that produced output.
for n = 1:numel(x)
    u = xp(padding+n+relative);
    z = w'*u;
    y(n) = z;
    railPhase = mod(n-1-offset,sps);
    if n <= padding+span*sps || n > numel(x)-padding-span*sps
        continue;
    end
    if railPhase == 0
        v = real(z);
        e = v*(1-v*v);
    elseif railPhase == hop
        v = imag(z);
        e = 1j*v*(1-v*v);
    else
        continue;
    end
    % Minimize the SAME rail cost with a bounded tap vector. Long blind
    % adaptation can drift in weakly excited T/2 regressor directions.
    % Enforce the existing norm constraint in the update, not by aborting
    % the link simulation. Do not increase the bound or discard frames.
    [wNext,accepted,constrained,candidateNorm] = HelperTMNormalizedTapUpdate( ...
        w,u,e,mu,real(u'*u)+1e-8,maxNorm,true);
    w = wNext;
    attempts = attempts+1;
    updates = updates+accepted;
    projectedUpdates = projectedUpdates+constrained;
    rejectedUpdates = rejectedUpdates+~accepted;
    if constrained && isnan(firstConstrainedSample), firstConstrainedSample=n; end
    maxCandidateNorm = max(maxCandidateNorm,candidateNorm);
    peakTapNorm = max(peakTapNorm,norm(w));
    costSum = costSum+(1-v*v)^2;
end
y = y*amplitude;
[i1,q1] = HelperTMOQPSKRailSamples(y,sps,span);
info = struct('Enabled',true,'Mode','oqpsk-staggered-cma', ...
    'NumTaps',taps,'CMAStep',mu,'CMASymbols',updates, ...
    'BlindCostMode','staggered-rail-cma', ...
    'EqualizerStructure','oqpsk-half-symbol-spaced-fir', ...
    'InputPower',mean(abs(matched).^2),'OutputPower',mean(abs(y).^2), ...
    'CMAMSE',costSum/max(attempts,1),'FinalTapNorm',norm(w), ...
    'UpdateAttempts',attempts,'ProjectedUpdates',projectedUpdates, ...
    'RejectedUpdates',rejectedUpdates,'PeakTapNorm',peakTapNorm, ...
    'MaxCandidateTapNorm',maxCandidateNorm,'MaxTapNorm',maxNorm, ...
    'FirstConstrainedSample',firstConstrainedSample, ...
    'InputStructureMSE',railMSE(i0,q0), ...
    'OutputStructureMSE',railMSE(i1,q1), ...
    'OutputAccepted',true,'Converged',false,'CMAQualified',false, ...
    'Reason',['OQPSK matched samples -> shared complex T/2 FIR; ', ...
    'alternating I/Q projected CMA updates; output used by soft demapper. ', ...
    'Applied/accepted do not establish convergence or zero BER.'], ...
    'SampleOffset',offset,'InputSamples',numel(x), ...
    'OutputSamples',numel(y),'LookaheadSamples',padding, ...
    'SamplesPerSymbol',sps,'Weights',w);
end

function x = value(s,name,fallback)
x = fallback;
if isfield(s,name) && ~isempty(s.(name)), x = double(s.(name)); end
end

function mse = railMSE(i,q)
a = sqrt(mean(i.^2+q.^2)/2+eps);
mse = mean((abs(i)/a-1).^2+(abs(q)/a-1).^2)/2;
end
