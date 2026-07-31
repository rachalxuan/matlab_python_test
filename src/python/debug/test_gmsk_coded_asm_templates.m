%% TEST_GMSK_CODED_ASM_TEMPLATES
% Fast transmitter-truth check for the convolutionally encoded ASM suffixes.
% No channel, synchronization loop, decoder, or BER sweep is run here.

clear classes
rng(20260715, 'twister');

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);

rates = {'1/2','2/3','3/4','5/6','7/8'};
numFrames = 12;
defaultNumBytesTF = 1115;
asmBits = localHexToBits('1ACFFC1D');
rows = cell(numel(rates), 7);

for rateIndex = 1:numel(rates)
    rate = rates{rateIndex};
    numBytesTF = defaultNumBytesTF;
    if strcmp(rate, '5/6')
        numBytesTF = 1116;
    elseif strcmp(rate, '7/8')
        numBytesTF = 1123;
    end
    tx = ccsdsTMWaveformGenerator( ...
        'WaveformSource', 'synchronization and channel coding', ...
        'NumBytesInTransferFrame', numBytesTF, ...
        'Modulation', 'GMSK', ...
        'ChannelCoding', 'convolutional', ...
        'ConvolutionalCodeRate', rate, ...
        'HasASM', true, 'RandomizerEnabled', false, ...
        'BandwidthTimeProduct', 0.5, 'SamplesPerSymbol', 8);
    msg = int8(randi([0 1], tx.NumInputBits*numFrames, 1));
    [~, encodedBits] = tx(msg);
    encodedBits = logical(encodedBits(:));

    markerCfg = gmsk_frame_reset_asm_config( ...
        'convolutional', rate, numBytesTF, asmBits, 'NRZ-L');
    [markerStarts, frameStarts, templateIds] = ...
        localFindExactTemplates(encodedBits, markerCfg);

    expectedFrames = min(numFrames, floor(numel(encodedBits) / ...
        (markerCfg.framePeriodBits-markerCfg.periodToleranceBits)));
    exactFrameStarts = unique(frameStarts(frameStarts >= 1));
    gaps = diff(exactFrameStarts);

    rows{rateIndex,1} = rate;
    rows{rateIndex,2} = numel(encodedBits);
    rows{rateIndex,3} = markerCfg.framePeriodBits;
    rows{rateIndex,4} = numel(markerCfg.asmTemplateCells);
    rows{rateIndex,5} = numel(exactFrameStarts);
    rows{rateIndex,6} = mat2str(unique(gaps).');
    rows{rateIndex,7} = mat2str(unique(templateIds).');

    fprintf(['rate=%s, encoded=%d, nominal period=%.4f, ', ...
        'templates=%d, exact frame markers=%d, gaps=%s\n'], ...
        rate, numel(encodedBits), markerCfg.framePeriodBits, ...
        numel(markerCfg.asmTemplateCells), numel(exactFrameStarts), ...
        mat2str(unique(gaps).'));

    assert(numel(markerStarts) >= expectedFrames-1, ...
        'Too few exact encoded-ASM suffixes found for rate %s.', rate);
end

summary = cell2table(rows, 'VariableNames', ...
    {'Rate','EncodedBits','NominalPeriod','TemplateCount', ...
     'ExactFrameMarkers','ObservedFrameGaps','UsedTemplateIds'});
disp(summary);
assignin('base', 'gmskCodedASMTemplateSummary', summary);
fprintf('[GMSK coded ASM templates] PASS\n');

function [markerStarts, frameStarts, templateIds] = ...
        localFindExactTemplates(bits, cfg)
    markerStarts = zeros(0,1);
    frameStarts = zeros(0,1);
    templateIds = zeros(0,1);
    bitsRow = double(bits(:).');
    for templateIndex = 1:numel(cfg.asmTemplateCells)
        template = double(cfg.asmTemplateCells{templateIndex}(:).');
        positions = strfind(bitsRow, template); %#ok<STRIFCND>
        for position = positions
            frameStart = position - cfg.asmOffsetBitsByTemplate(templateIndex);
            markerStarts(end+1,1) = position; %#ok<AGROW>
            frameStarts(end+1,1) = frameStart; %#ok<AGROW>
            templateIds(end+1,1) = templateIndex; %#ok<AGROW>
        end
    end

    [~, order] = sort(frameStarts);
    markerStarts = markerStarts(order);
    frameStarts = frameStarts(order);
    templateIds = templateIds(order);
end

function bits = localHexToBits(hexValue)
    hexValue = upper(char(hexValue));
    bits = false(4*numel(hexValue), 1);
    out = 1;
    for k = 1:numel(hexValue)
        value = hex2dec(hexValue(k));
        bits(out:out+3) = logical(bitget(uint8(value), 4:-1:1).');
        out = out + 4;
    end
end
