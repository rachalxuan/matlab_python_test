function [y,cfoEstimate,info] = robustPSKCoarseFrequencyCompensator( ...
        x,sampleRateHz,modType,maximumFrequencyOffsetHz)
%ROBUSTPSKCOARSEFREQUENCYCOMPENSATOR Robust NDA CFO acquisition for PSK.
%
%   [Y,CFO,INFO] = robustPSKCoarseFrequencyCompensator( ...
%       X,FS,MODTYPE,MAXCFO)
%
%   This helper is deliberately limited to BPSK, QPSK, and 8PSK.  It uses
%   the correlation-based mode of comm.CoarseFrequencyCompensator on seven
%   windows spread across the complete observation.  The correlation vote
%   supplies a rough center; an m-th-power FFT then refines the estimate
%   inside the best-supported interval.  A globally consistent FFT vote
%   remains as a wide-offset fallback.  Otherwise the input is returned
%   unchanged.
%
%   This prevents an unrestricted global m-th-power spectral peak from
%   becoming the correction merely because it is the largest peak.  The
%   multi-window vote rejects local fades and other short nonstationary
%   intervals.  It cannot prove that a consensus estimate is physically
%   correct; INFO therefore exposes all estimates for diagnosis.

x = x(:);
y = x;
cfoEstimate = 0;

if nargin < 4 || isempty(maximumFrequencyOffsetHz)
    maximumFrequencyOffsetHz = 2e6;
end

if ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
    error('robustPSKCoarseFrequencyCompensator:InvalidSampleRate', ...
        'sampleRateHz must be a positive finite scalar.');
end
if ~(isscalar(maximumFrequencyOffsetHz) && ...
        isfinite(maximumFrequencyOffsetHz) && ...
        maximumFrequencyOffsetHz > 0)
    error('robustPSKCoarseFrequencyCompensator:InvalidCaptureRange', ...
        'maximumFrequencyOffsetHz must be a positive finite scalar.');
end
modType = upper(strtrim(char(string(modType))));
validModulations = {'BPSK','QPSK','8PSK'};
if ~any(strcmp(modType,validModulations))
    error('robustPSKCoarseFrequencyCompensator:UnsupportedModulation', ...
        'modType must be BPSK, QPSK, or 8PSK.');
end

switch modType
    case 'BPSK'
        powerOrder = 2;
    case 'QPSK'
        powerOrder = 4;
    otherwise
        powerOrder = 8;
end

numberOfSegments = 7;
requiredConsistentSegments = 5;
nominalSegmentLength = 65536;
minimumSegmentLength = 1024;
segmentLength = min(nominalSegmentLength, ...
    floor(numel(x)/numberOfSegments));

% The correlation estimate is deliberately used only as a rough center.
% Its phase statistic can be biased by pulse shaping and multipath, whereas
% the FFT is precise but can select the wrong data/multipath spectral peak.
correlationConsistencyToleranceHz = max(25e3, ...
    min(100e3,0.05*maximumFrequencyOffsetHz));
refinementSearchHalfWidthHz = max(50e3, ...
    min(300e3,0.15*maximumFrequencyOffsetHz));
consistencyToleranceHz = max(1e3, ...
    min(25e3,0.02*maximumFrequencyOffsetHz));

info = struct( ...
    'Attempted',true, ...
    'Accepted',false, ...
    'Applied',false, ...
    'Reason','', ...
    'Estimator','bounded-correlation-plus-local-mth-power-fft', ...
    'Modulation',modType, ...
    'PowerOrder',powerOrder, ...
    'MaximumFrequencyOffsetHz',maximumFrequencyOffsetHz, ...
    'NumberOfSegments',numberOfSegments, ...
    'RequiredConsistentSegments',requiredConsistentSegments, ...
    'SegmentLengthSamples',segmentLength, ...
    'SegmentStartIndices',zeros(numberOfSegments,1), ...
    'SegmentEstimatesHz',nan(numberOfSegments,1), ...
    'CorrelationSegmentEstimatesHz',nan(numberOfSegments,1), ...
    'CorrelationCandidateHz',NaN, ...
    'CorrelationConsistentSegmentMask',false(numberOfSegments,1), ...
    'CorrelationConsistencyToleranceHz', ...
        correlationConsistencyToleranceHz, ...
    'RefinementSearchHalfWidthHz',refinementSearchHalfWidthHz, ...
    'RefinementPeakConfidenceDB',nan(numberOfSegments,1), ...
    'GlobalFFTEstimatesHz',nan(numberOfSegments,1), ...
    'GlobalFFTPeakConfidenceDB',nan(numberOfSegments,1), ...
    'GlobalFFTConsistentSegmentMask',false(numberOfSegments,1), ...
    'GlobalFFTCandidateHz',NaN, ...
    'AcceptancePath','none', ...
    'ValidSegmentMask',false(numberOfSegments,1), ...
    'ConsistentSegmentMask',false(numberOfSegments,1), ...
    'ConsistencyToleranceHz',consistencyToleranceHz, ...
    'CandidateHz',NaN, ...
    'EstimateHz',0);

if segmentLength < minimumSegmentLength
    info.Reason = sprintf( ...
        'input too short: %d samples per segment (minimum %d)', ...
        segmentLength,minimumSegmentLength);
    return;
end

% Distribute the windows over the full record instead of examining only
% the first few milliseconds of a long time-varying channel realization.
lastStart = numel(x)-segmentLength+1;
segmentStarts = round(linspace(1,lastStart,numberOfSegments)).';
correlationEstimates = nan(numberOfSegments,1);

for k = 1:numberOfSegments
    sampleIndices = segmentStarts(k) + (0:segmentLength-1);
    segment = x(sampleIndices);

    estimator = comm.CoarseFrequencyCompensator( ...
        'Modulation',modType, ...
        'Algorithm','Correlation-based', ...
        'MaximumFrequencyOffset',maximumFrequencyOffsetHz, ...
        'SampleRate',sampleRateHz);
    [~,correlationEstimates(k)] = estimator(segment);
end

rangeToleranceHz = max(1,32*eps(maximumFrequencyOffsetHz));
correlationValid = isfinite(correlationEstimates) & ...
    abs(correlationEstimates) <= ...
    maximumFrequencyOffsetHz+rangeToleranceHz;

info.SegmentStartIndices = segmentStarts;
info.CorrelationSegmentEstimatesHz = correlationEstimates;

correlationCandidate = NaN;
correlationConsistent = false(numberOfSegments,1);
if nnz(correlationValid) >= requiredConsistentSegments
    correlationCandidate = median(correlationEstimates(correlationValid));
    correlationConsistent = correlationValid & ...
        abs(correlationEstimates-correlationCandidate) <= ...
        correlationConsistencyToleranceHz;
end

info.CorrelationCandidateHz = correlationCandidate;
info.CorrelationConsistentSegmentMask = correlationConsistent;

if nnz(correlationConsistent) >= requiredConsistentSegments
    refinementCenterHz = correlationCandidate;
else
    refinementCenterHz = NaN;
end

% Refine only near the robust correlation center.  This is the essential
% difference from the old global FFT estimator: a remote, higher spectral
% line is not eligible to become the CFO correction.
segmentEstimates = nan(numberOfSegments,1);
peakConfidenceDB = nan(numberOfSegments,1);
globalFFTEstimates = nan(numberOfSegments,1);
globalFFTPeakConfidenceDB = nan(numberOfSegments,1);
nfft = 2^nextpow2(segmentLength);
raisedFrequencyHz = (-nfft/2:nfft/2-1).' * ...
    (sampleRateHz/nfft);
cfoFrequencyHz = raisedFrequencyHz/powerOrder;
searchMask = abs(cfoFrequencyHz) <= ...
    maximumFrequencyOffsetHz+rangeToleranceHz & ...
    abs(cfoFrequencyHz-refinementCenterHz) <= ...
    refinementSearchHalfWidthHz;

window = hamming(segmentLength,'periodic');
% Global FFT votes are independent of the rough correlation consensus.
% Gating them with correlation would discard a recoverable line after CMA.
for k = 1:numberOfSegments
    sampleIndices = segmentStarts(k) + (0:segmentLength-1);
    segment = x(sampleIndices);
    segmentScale = sqrt(mean(abs(segment).^2));
    if ~(isfinite(segmentScale) && segmentScale > realmin('double'))
        continue;
    end
    raised = (segment/segmentScale).^powerOrder;
    spectrumPower = abs(fftshift(fft(raised.*window,nfft))).^2;
    globalMask = abs(cfoFrequencyHz) <= ...
        maximumFrequencyOffsetHz+rangeToleranceHz;
    globalPower = spectrumPower(globalMask);
    globalFrequencies = cfoFrequencyHz(globalMask);
    [globalPeakPower,globalPeakIndex] = max(globalPower);
    globalFFTEstimates(k) = globalFrequencies(globalPeakIndex);
    globalFFTPeakConfidenceDB(k) = 10*log10( ...
        max(globalPeakPower,realmin)/ ...
        max(median(globalPower),realmin));
    if any(searchMask) && correlationConsistent(k)
        localPower = spectrumPower(searchMask);
        localFrequencies = cfoFrequencyHz(searchMask);
        [peakPower,peakIndex] = max(localPower);
        segmentEstimates(k) = localFrequencies(peakIndex);
        peakConfidenceDB(k) = 10*log10( ...
            max(peakPower,realmin)/max(median(localPower),realmin));
    end
end

valid = isfinite(segmentEstimates) & isfinite(peakConfidenceDB) & ...
    peakConfidenceDB >= 3;
globalValid = isfinite(globalFFTEstimates) & ...
    isfinite(globalFFTPeakConfidenceDB) & ...
    globalFFTPeakConfidenceDB >= 3;
info.SegmentEstimatesHz = segmentEstimates;
info.RefinementPeakConfidenceDB = peakConfidenceDB;
info.GlobalFFTEstimatesHz = globalFFTEstimates;
info.GlobalFFTPeakConfidenceDB = globalFFTPeakConfidenceDB;
info.ValidSegmentMask = valid;

localConsistent = false(numberOfSegments,1);
if nnz(valid) >= requiredConsistentSegments
    localCandidate = median(segmentEstimates(valid));
    localConsistent = valid & ...
        abs(segmentEstimates-localCandidate) <= consistencyToleranceHz;
end

globalCandidate = NaN;
globalConsistent = false(numberOfSegments,1);
if nnz(globalValid) >= requiredConsistentSegments
    globalCandidate = median(globalFFTEstimates(globalValid));
    globalConsistent = globalValid & ...
        abs(globalFFTEstimates-globalCandidate) <= ...
        consistencyToleranceHz;
end
info.GlobalFFTCandidateHz = globalCandidate;
info.GlobalFFTConsistentSegmentMask = globalConsistent;

if nnz(localConsistent) >= requiredConsistentSegments
    cfoEstimate = median(segmentEstimates(localConsistent));
    selectedConsistent = localConsistent;
    info.AcceptancePath = 'bounded-local-refinement';
elseif nnz(globalConsistent) >= requiredConsistentSegments
    % This path preserves wide-offset No-H acquisition.  Unlike the former
    % single global FFT, the peak must recur in at least five windows spread
    % over the complete record before it is allowed to rotate the waveform.
    cfoEstimate = median(globalFFTEstimates(globalConsistent));
    selectedConsistent = globalConsistent;
    info.AcceptancePath = 'global-multiwindow-fallback';
else
    info.Reason = sprintf( ...
        ['no CFO consensus: local=%d/%d, global=%d/%d ', ...
         '(tolerance %.1f Hz)'], ...
        nnz(localConsistent),numberOfSegments, ...
        nnz(globalConsistent),numberOfSegments, ...
        consistencyToleranceHz);
    return;
end

info.CandidateHz = cfoEstimate;
info.ConsistentSegmentMask = selectedConsistent;
% M-th-power acquisition is ambiguous modulo Fs/M. At a symbol-rate FSE
% output the alias spacing is smaller than at the oversampled raw input.
% Reject a vote if another alias also lies inside the configured capture
% interval; consensus by itself cannot resolve this physical ambiguity.
aliasesHz = cfoEstimate+[-1 1]*(sampleRateHz/powerOrder);
if any(abs(aliasesHz) <= maximumFrequencyOffsetHz+rangeToleranceHz)
    info.Reason = sprintf( ...
        'CFO alias ambiguity inside +/-%.1f Hz capture range',maximumFrequencyOffsetHz);
    cfoEstimate = 0;
    return;
end
sampleIndex = (0:numel(x)-1).';
y = x .* exp(-1j*2*pi*cfoEstimate*sampleIndex/sampleRateHz);

info.Accepted = true;
info.Applied = true;
info.Reason = sprintf('%s: %d/%d segment estimates agreed', ...
    info.AcceptancePath,nnz(selectedConsistent),numberOfSegments);
info.EstimateHz = cfoEstimate;
end
