function variance = HelperTMPSKResidualVariance(symbols, constellation)
% Receiver-only equivalent complex residual variance for PSK soft metrics.
% Include ISI/tracking error as well as additive noise. Work in the SAME
% amplitude units as the demapper; do not normalize this diagnostic copy or
% use configured SNR, H, transmitted bits, or measured decoder BER.
z=complex(symbols(:)); c=complex(constellation(:));
z=z(isfinite(real(z)) & isfinite(imag(z)));
if isempty(z) || isempty(c)
    variance=1;
    return;
end
% Accumulate in bounded blocks, including poor/startup samples instead of
% discarding the largest residuals and overstating confidence.
total=0;
for first=1:8192:numel(z)
    part=z(first:min(numel(z),first+8191));
    distance2=min(abs(part-c.').^2,[],2);
    total=total+sum(distance2);
end
% This decision-directed estimate is not an unbiased physical noise meter
% and cannot detect a whole-constellation cycle slip. LLR clipping in the
% demapper bounds its confidence in clean or nearly noise-free records.
variance=max(1e-4,total/numel(z));
end
