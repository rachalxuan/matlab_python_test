function coverage = HelperTMMeasurementCoverage(observations)
% Unique requested TX slots, NOT merely a count of decoder deliveries.
coverage = struct('Available',false,'Status','UNAVAILABLE', ...
    'ExpectedFrames',NaN,'RecoveredFrames',NaN,'ComparedFrames',NaN, ...
    'UnrecoveredFrames',NaN,'RecoveredNotComparedFrames',NaN, ...
    'DuplicateComparisons',NaN,'ComparedBits',NaN,'Fraction',NaN,'Complete',false);
if isempty(observations), return; end
expected=0; recovered=0; compared=0; duplicates=0; bits=0;
for k=1:numel(observations)
    o=observations{k}; n=double(o.ExpectedFrames);
    first=double(o.FirstMeasurementFrame);
    tx=double(o.TxFrameIndex(:)); counted=logical(o.Counted(:));
    valid=isfinite(tx) & tx>=first & tx<=n & tx==floor(tx);
    expected=expected+max(0,n-first+1);
    recovered=recovered+numel(unique(tx(valid)));
    ids=tx(valid & counted);
    compared=compared+numel(unique(ids));
    duplicates=duplicates+numel(ids)-numel(unique(ids));
    bits=bits+numel(ids)*double(o.PayloadBitsPerFrame);
end
coverage.Available=true;
coverage.ExpectedFrames=expected;
coverage.RecoveredFrames=recovered;
coverage.ComparedFrames=compared;
coverage.UnrecoveredFrames=expected-recovered;
coverage.RecoveredNotComparedFrames=recovered-compared;
coverage.DuplicateComparisons=duplicates;
coverage.ComparedBits=bits;
coverage.Fraction=compared/max(1,expected);
coverage.Complete=expected>0 && compared==expected && duplicates==0;
coverage.Status='MEASUREMENT_INCOMPLETE';
if coverage.Complete, coverage.Status='COMPLETE'; end
end
