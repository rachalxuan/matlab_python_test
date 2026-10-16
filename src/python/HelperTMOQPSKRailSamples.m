function [iSamples,qSamples,bestOffset] = HelperTMOQPSKRailSamples(matched,sps,span)
% Receiver-only timing selection shared by OQPSK demapping and equalization.
% I and Q eye centers are always separated by half a symbol. No TX truth.
bestScore = inf;
bestOffset = 0;
iSamples = zeros(0,1);
qSamples = zeros(0,1);
for offset = 0:sps-1
    iCandidate = real(matched(1+offset:sps:end));
    qCandidate = imag(matched(1+offset+sps/2:sps:end));
    n = min(numel(iCandidate),numel(qCandidate));
    if n <= max(8,2*span), continue; end
    iCandidate = iCandidate(1:n);
    qCandidate = qCandidate(1:n);
    guard = min(span,floor((n-1)/4));
    use = (1+guard):(n-guard);
    amplitude = sqrt(mean(iCandidate(use).^2+qCandidate(use).^2)/2+eps);
    score = mean((abs(iCandidate(use))-amplitude).^2 + ...
        (abs(qCandidate(use))-amplitude).^2)/(2*amplitude^2+eps);
    if score < bestScore
        bestScore = score;
        bestOffset = offset;
        iSamples = iCandidate;
        qSamples = qCandidate;
    end
end
end
