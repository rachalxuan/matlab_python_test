function [rawMetric, info] = gmsk_official_viterbi_raw_metric(inputWaveform, cfg)
%GMSK_OFFICIAL_VITERBI_RAW_METRIC Recover CCSDS GMSK precoder symbols.
%
% The production transmitter applies the CCSDS transition precoder before
% comm.GMSKModulator(BitInput=false).  comm.GMSKDemodulator therefore
% recovers the bipolar precoder symbols, not the original coded bits.  This
% helper removes the fixed Viterbi traceback delay and converts the symbol
% polarity to the raw-metric convention expected by
% gmsk_frame_reset_demodulate:
%
%   positive raw metric -> raw bit 0
%   negative raw metric -> raw bit 1
%
% The output remains a hard metric because comm.GMSKDemodulator does not
% expose a soft-output LLR interface.

    if nargin < 2 || isempty(cfg)
        cfg = struct();
    end

    samplesPerSymbol = localField(cfg, 'SamplesPerSymbol', 8);
    bt = localField(cfg, 'BandwidthTimeProduct', 0.5);
    pulseLength = localField(cfg, 'PulseLength', localPulseLength(bt));
    tracebackDepth = localField(cfg, 'TracebackDepth', 32);
    outputScale = localField(cfg, 'OutputScale', 5);

    samplesPerSymbol = max(1, round(double(samplesPerSymbol)));
    pulseLength = max(1, round(double(pulseLength)));
    tracebackDepth = max(1, round(double(tracebackDepth)));
    outputScale = max(eps, double(outputScale));

    inputWaveform = inputWaveform(:);
    info = struct( ...
        'SamplesPerSymbol', samplesPerSymbol, ...
        'BandwidthTimeProduct', double(bt), ...
        'PulseLength', pulseLength, ...
        'TracebackDepth', tracebackDepth, ...
        'InputSamples', numel(inputWaveform), ...
        'DemodulatedSymbols', 0, ...
        'OutputSymbols', 0, ...
        'DroppedTracebackSymbols', 0, ...
        'ZeroDecisions', 0);

    if isempty(inputWaveform)
        rawMetric = zeros(0, 1);
        return;
    end

    demodulator = comm.GMSKDemodulator( ...
        'BitOutput', false, ...
        'BandwidthTimeProduct', double(bt), ...
        'PulseLength', pulseLength, ...
        'SymbolPrehistory', 1, ...
        'InitialPhaseOffset', 0, ...
        'SamplesPerSymbol', samplesPerSymbol, ...
        'TracebackDepth', tracebackDepth, ...
        'OutputDataType', 'double');

    recoveredSymbols = double(demodulator(inputWaveform));
    release(demodulator);
    recoveredSymbols = recoveredSymbols(:);
    info.DemodulatedSymbols = numel(recoveredSymbols);

    % MATLAB's GMSK Viterbi output is delayed by TracebackDepth symbols.
    % Removing the leading delayed decisions aligns output symbol 1 with
    % the first transmitted precoder symbol; the final tracebackDepth input
    % symbols have no flushed decisions and are intentionally omitted.
    drop = min(tracebackDepth, numel(recoveredSymbols));
    recoveredSymbols = recoveredSymbols(drop+1:end);
    info.DroppedTracebackSymbols = drop;

    hardSymbols = sign(recoveredSymbols);
    info.ZeroDecisions = nnz(hardSymbols == 0);

    % TX bipolar precoder symbol p maps to the existing receiver's raw
    % metric as rawMetric=-p.  This polarity was verified against the
    % production ccsdsTMWaveformGenerator in the ideal-link short test.
    rawMetric = -outputScale * hardSymbols;
    rawMetric = double(rawMetric(:));
    info.OutputSymbols = numel(rawMetric);
end

function value = localField(s, name, defaultValue)
    if isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = defaultValue;
    end
end

function pulseLength = localPulseLength(bt)
    if abs(double(bt) - 0.5) < 1e-12
        pulseLength = 2;
    else
        % Matches ccsdsTMWaveformGenerator for the supported BT=0.25 case.
        pulseLength = 3;
    end
end
