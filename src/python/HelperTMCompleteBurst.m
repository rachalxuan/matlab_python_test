function [waveform, info, continuationEncodedBits] = HelperTMCompleteBurst(generator, waveform, encodedBits, inputBits, Fs, options)
% Complete the MEASURED burst by transmitting an unmeasured continuation.
% Keep the original waveform prefix bit-for-bit. Reuse the SAME generator
% (encoder, mapper and pulse-shaping states); padding RX soft bits cannot
% recover information that is still buffered at TX. Guard data are NOT
% appended to the evaluator's TX reference or encoded-bit reference.
continuationEncodedBits = zeros(0,1,'int8');
rawGeneratorSamples = numel(waveform);
[waveform, rectangularHoldApplied] = localApplyUnshapedSymbolHold( ...
    generator,waveform);
info = struct('Applied',false,'Reason','dedicated waveform path unchanged', ...
    'OriginalWaveformSamples',numel(waveform),'OriginalEncodedBits',numel(encodedBits), ...
    'OriginalModulatedBits',NaN,'BufferedModulationBits',NaN, ...
    'GuardInputGroups',0,'AppendedSamples',0,'AppendedEncodedBits',0, ...
    'MeasurementDuration_s',numel(waveform)/Fs, ...
    'GeneratorOutputSamplesBeforeHold',rawGeneratorSamples, ...
    'RectangularSymbolHoldApplied',rectangularHoldApplied);
linearMods = ["BPSK","QPSK","8PSK","16QAM","32QAM","16APSK","32APSK","OQPSK","UQPSK"];
% New pulse choices are validated on combined TM first. Preserve legacy
% staggered/unequal split continuation until its per-rail contract is tested.
if any(strcmpi(generator.Modulation,{'OQPSK','UQPSK'})) && ...
        ~strcmpi(generator.DataPathMode,'single')
    return;
end
if ~any(string(generator.Modulation)==linearMods) || ...
        string(generator.WaveformSource)~="synchronization and channel coding" || ...
        generator.HasTMAPSKPilots || ...
        (strcmpi(generator.ChannelCoding,'LDPC') && generator.IsLDPCOnSMTF)
    return;
end
wi = infoOf(generator);
bitsPerSymbol = double(wi.NumBitsPerSymbol);
sps = double(generator.SamplesPerSymbol);
info.OriginalModulatedBits = numel(waveform)/sps*bitsPerSymbol;
info.BufferedModulationBits = numel(encodedBits)-info.OriginalModulatedBits;
info.MeasurementDuration_s = numel(encodedBits)/bitsPerSymbol/(Fs/sps);
groupBits = double(generator.NumInputBits);
groups = numel(inputBits)/groupBits;
assert(groups>=1 && groups==floor(groups),'TMCompleteBurst:InputGroups', ...
    'A measured burst must contain complete generator input groups.');
groupSymbols = max(1,numel(encodedBits)/groups/bitsPerSymbol);
% One additional group releases block buffering; another covers RX frame
% buffering/traceback. Grow the guard for explicitly long timing/FIR delays.
memorySymbols = 256 + max(0,number(options,'delay',0))/sps + ...
    max(0,number(options,'adaptiveFractionalEqualizerTaps',49))/2 + ...
    max(0,number(options,'adaptiveFractionalPostForwardTaps',9));
if any(strcmpi(generator.Modulation,{'OQPSK','UQPSK'}))
    pulse = HelperTMPulseShapeConfig(generator.PulseShapingFilter,sps, ...
        double(generator.RolloffFactor),double(generator.FilterSpanInSymbols));
    memorySymbols = memorySymbols + 2*pulse.TransientSymbols + 1;
end
guardGroups = max([2, double(generator.MinNumTransferFrames), ...
    1+ceil(memorySymbols/groupSymbols)]);
inputBits = int8(inputBits(:));
if strcmpi(generator.DataPathMode,'dualIQ')
    half = numel(inputBits)/2; railBits=groupBits/2;
    guard = [repmat(inputBits(half-railBits+1:half),guardGroups,1); ...
        repmat(inputBits(end-railBits+1:end),guardGroups,1)];
else
    guard = repmat(inputBits(end-groupBits+1:end),guardGroups,1);
end
% Use DIFFERENT information bits, so a guard cannot masquerade as a lost
% final reference frame. The normal encoder still creates valid codewords.
% Guard headers need not describe a business TF: they are never measured.
guard = int8(1)-guard;
% This consumes no RNG and changes no measured header/payload.
[continuation, continuationEncodedBits] = generator(guard);
[continuation, continuationHoldApplied] = localApplyUnshapedSymbolHold( ...
    generator,continuation);
assert(continuationHoldApplied == rectangularHoldApplied, ...
    'TMCompleteBurst:PulseShapingMismatch', ...
    'Measured and continuation waveforms used different pulse-shaping adapters.');
waveform = [waveform(:);continuation(:)];
info.Applied = true;
info.Reason = 'state-preserving TX continuation; guard groups excluded from measurement';
info.GuardInputGroups = guardGroups;
info.AppendedSamples = numel(continuation);
info.AppendedEncodedBits = numel(continuationEncodedBits);
end

function [waveform, applied] = localApplyUnshapedSymbolHold(generator,waveform)
% The generator's documented "none" mode returns one complex sample per
% symbol.  The rest of this evaluator has a fixed Fs = symbolRate*SPS
% contract, so represent an unshaped symbol stream as an SPS-sample
% rectangular pulse (zero-order hold).  Do not touch CPM/OQPSK/dedicated
% waveform paths whose generator output is already oversampled.
supported = ["BPSK","QPSK","8PSK","16QAM","32QAM","UQPSK"];
applied = strcmpi(string(generator.PulseShapingFilter),"none") && ...
    any(strcmpi(string(generator.Modulation),supported));
waveform = waveform(:);
if applied
    waveform = repelem(waveform,double(generator.SamplesPerSymbol));
end
end

function s = infoOf(g)
s = info(g);
end

function v = number(s,name,defaultValue)
v=defaultValue;
if isfield(s,name) && isnumeric(s.(name)) && isscalar(s.(name)) && isfinite(s.(name))
    v=double(s.(name));
end
end
