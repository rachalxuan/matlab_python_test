function [y, info] = HelperTMSymbolSynchronizerChunked(x, cfg)
%HELPERTMSYMBOLSYNCHRONIZERCHUNKED Run comm.SymbolSynchronizer in chunks.
%
% Keeping one System object across chunks preserves Gardner loop state while
% preventing MATLAB's variable-size output limit from dropping the tail of a
% long waveform.  This is an internal receiver utility; it has no front-end
% configuration surface.

x = x(:);
if nargin < 2 || ~isstruct(cfg)
    cfg = struct();
end

samplesPerSymbol = localNumber(cfg,'SamplesPerSymbol',2);
detectorGain = localNumber(cfg,'DetectorGain',1);
loopBandwidth = localNumber(cfg,'NormalizedLoopBandwidth',0.01);
modulation = localString(cfg,'Modulation','PAM/PSK/QAM');
chunkSize = max(4096, round(localNumber(cfg,'ChunkSizeSamples',50000)));

info = struct('InputSamples',numel(x), ...
    'OutputSamples',0, ...
    'ChunkSizeSamples',chunkSize, ...
    'NumChunks',0, ...
    'ExpectedSymbols',numel(x)/max(samplesPerSymbol,eps), ...
    'RateError_ppm',NaN);

if isempty(x)
    y = x;
    return;
end

timingObj = comm.SymbolSynchronizer( ...
    'TimingErrorDetector','Gardner (non-data-aided)', ...
    'SamplesPerSymbol',samplesPerSymbol, ...
    'DetectorGain',detectorGain, ...
    'Modulation',modulation, ...
    'NormalizedLoopBandwidth',loopBandwidth);

numChunks = ceil(numel(x)/chunkSize);
numPadded = numChunks*chunkSize;
xPadded = zeros(numPadded,1,'like',x);
xPadded(1:numel(x)) = x;

parts = cell(numChunks,1);
nParts = 0;
for first = 1:chunkSize:numPadded
    last = first+chunkSize-1;
    nParts = nParts + 1;
    % All calls have the same input size.  The final zero padding only
    % flushes the loop state; its output is removed below.
    parts{nParts} = timingObj(xPadded(first:last));
end

parts = parts(1:nParts);
y = vertcat(parts{:});
expectedOutput = max(1,round(numel(x)/max(samplesPerSymbol,eps)));
y = y(1:min(numel(y),expectedOutput));
info.OutputSamples = numel(y);
info.NumChunks = nParts;
info.RateError_ppm = 1e6*(numel(y)-info.ExpectedSymbols)/ ...
    max(info.ExpectedSymbols,1);
end

function v = localNumber(s,name,defaultValue)
v = defaultValue;
if isfield(s,name) && ~isempty(s.(name))
    raw = s.(name);
    if isnumeric(raw) || islogical(raw)
        raw = double(raw(1));
        if isfinite(raw), v = raw; end
    end
end
end

function v = localString(s,name,defaultValue)
v = defaultValue;
if isfield(s,name) && ~isempty(s.(name))
    raw = s.(name);
    if ischar(raw) || isstring(raw)
        v = char(string(raw));
    end
end
end
