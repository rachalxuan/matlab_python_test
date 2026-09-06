function cfg = gmsk_frame_reset_asm_config(channelCoding, codeRate, ...
        numBytesInTransferFrame, asmBits, pcmFormat, codingCfg)
%GMSK_FRAME_RESET_ASM_CONFIG Build known ASM suffixes for GMSK state reset.
%
% The convolutional encoder is continuous, so its first six ASM input bits
% depend on the previous trellis state.  After those six bits, the encoder
% memory contains ASM bits only.  This function therefore returns the known
% transmitted suffix together with the number of punctured prefix bits that
% precede it.  Standard aligned frames use phase zero; all phases are kept as
% a diagnostic fallback only when a non-standard frame length is supplied.

    if nargin < 1 || isempty(channelCoding), channelCoding = 'none'; end
    if nargin < 2 || isempty(codeRate), codeRate = '1/2'; end
    if nargin < 3 || isempty(numBytesInTransferFrame)
        numBytesInTransferFrame = 1115;
    end
    if nargin < 4 || isempty(asmBits)
        asmBits = localStandardASM(channelCoding, codeRate);
    end
    if nargin < 5 || isempty(pcmFormat), pcmFormat = 'NRZ-L'; end
    if nargin < 6 || isempty(codingCfg), codingCfg = struct(); end

    asmBits = logical(asmBits(:));
    codeKey = lower(string(channelCoding));
    pcmFormat = upper(string(pcmFormat));
    inputFrameBits = double(numBytesInTransferFrame)*8 + numel(asmBits);

    cfg = struct();
    cfg.asmTemplateCells = {asmBits};
    cfg.asmOffsetBitsByTemplate = 0;
    cfg.asmTemplatePuncturePhase = 0;
    cfg.framePeriodBits = inputFrameBits;
    cfg.periodToleranceBits = 0;
    cfg.channelCoding = char(channelCoding);
    cfg.codeRate = char(codeRate);
    cfg.pcmFormat = char(pcmFormat);

    % Ordinary TM LDPC and Turbo frames place the raw ASM outside the
    % encoded codeword.  Their GMSK frame-reset template is therefore the
    % raw ASM; only the exact coded frame period differs by code family.
    if codeKey == "ldpc" || codeKey == "turbo"
        informationBits = localPositiveIntegerField( ...
            codingCfg, 'NumBitsInInformationBlock');
        if codeKey == "ldpc"
            codewordBits = localLDPCCodewordLength( ...
                informationBits, codeRate);
        else
            codewordBits = localTurboCodewordLength( ...
                informationBits, codeRate);
        end

        cfg.asmTemplates = asmBits;
        cfg.asmOffsetBits = 0;
        cfg.framePeriodBits = numel(asmBits) + codewordBits;
        cfg.informationBlockLength = informationBits;
        cfg.codewordLength = codewordBits;
        cfg.frameLayout = 'raw-asm-coded-payload';
        return;
    end

    % RS frames also place the raw ASM ahead of one interleaved RS
    % codeword.  GMSK detection itself is independent of the FEC family;
    % these parameters are needed only to establish the periodic ASM grid.
    if codeKey == "rs"
        rsMessageLength = localPositiveIntegerField( ...
            codingCfg, 'RSMessageLength');
        rsInterleavingDepth = localPositiveIntegerField( ...
            codingCfg, 'RSInterleavingDepth');
        isShortened = localLogicalField(codingCfg, ...
            'IsRSMessageShortened', false);
        if isShortened
            rsShortenedMessageLength = localPositiveIntegerField( ...
                codingCfg, 'RSShortenedMessageLength');
        else
            rsShortenedMessageLength = rsMessageLength;
        end
        localValidateRSConfiguration(rsMessageLength, ...
            rsInterleavingDepth, rsShortenedMessageLength);

        rsCodewordBytes = rsInterleavingDepth * ...
            (255 - rsMessageLength + rsShortenedMessageLength);
        codewordBits = 8 * rsCodewordBytes;

        cfg.asmTemplates = asmBits;
        cfg.asmOffsetBits = 0;
        cfg.framePeriodBits = numel(asmBits) + codewordBits;
        cfg.codewordLength = codewordBits;
        cfg.RSMessageLength = rsMessageLength;
        cfg.RSInterleavingDepth = rsInterleavingDepth;
        cfg.IsRSMessageShortened = isShortened;
        cfg.RSShortenedMessageLength = rsShortenedMessageLength;
        cfg.frameLayout = 'raw-asm-rs-codeword';
        return;
    end

    % A concatenated TM frame is raw ASM followed by an RS codeword, then
    % a continuous convolutional encoder.  Unlike an RS-only frame, its
    % ASM is therefore convolutionally encoded and needs the same trellis
    % state-reset template as a convolutional frame.  Its period, however,
    % is based on the RS codeword length rather than payload bytes.
    if codeKey == "concatenated"
        rsMessageLength = localPositiveIntegerField( ...
            codingCfg, 'RSMessageLength');
        rsInterleavingDepth = localPositiveIntegerField( ...
            codingCfg, 'RSInterleavingDepth');
        isShortened = localLogicalField(codingCfg, ...
            'IsRSMessageShortened', false);
        if isShortened
            rsShortenedMessageLength = localPositiveIntegerField( ...
                codingCfg, 'RSShortenedMessageLength');
        else
            rsShortenedMessageLength = rsMessageLength;
        end
        localValidateRSConfiguration(rsMessageLength, ...
            rsInterleavingDepth, rsShortenedMessageLength);

        rsCodewordBytes = rsInterleavingDepth * ...
            (255 - rsMessageLength + rsShortenedMessageLength);
        inputFrameBits = numel(asmBits) + 8*rsCodewordBytes;
        cfg.RSMessageLength = rsMessageLength;
        cfg.RSInterleavingDepth = rsInterleavingDepth;
        cfg.IsRSMessageShortened = isShortened;
        cfg.RSShortenedMessageLength = rsShortenedMessageLength;
        cfg.codewordLength = 8*rsCodewordBytes;
        cfg.frameLayout = 'conv-encoded-raw-asm-rs-codeword';
    end

    % TPC frames also keep their ASM outside the product-code blocks.  One
    % transfer frame carries one or more fixed (64,57)^2 codewords.
    if codeKey == "tpc"
        blocksPerTF = localPositiveIntegerField(codingCfg, ...
            'TPCBlocksPerTF');
        codewordBits = 64 * 64 * blocksPerTF;

        cfg.asmTemplates = asmBits;
        cfg.asmOffsetBits = 0;
        cfg.framePeriodBits = numel(asmBits) + codewordBits;
        cfg.codewordLength = codewordBits;
        cfg.TPCBlocksPerTF = blocksPerTF;
        cfg.frameLayout = 'raw-asm-tpc-codewords';
        return;
    end

    if ~contains(codeKey, 'convolutional') && codeKey ~= "concatenated"
        cfg.asmTemplates = asmBits;
        cfg.asmOffsetBits = 0;
        return;
    end

    [rateValue, puncturePattern, flipSecondBranch] = ...
        localRateConfiguration(codeRate);
    inputPeriod = numel(puncturePattern) / 2;
    trellis = poly2trellis(7, [171 133]);

    if any(strcmp(pcmFormat, ["NRZ-M","NRZ-S"]))
        pcmInitialStates = [0 1];
    else
        pcmInitialStates = 0;
    end

    templates = cell(0, 1);
    offsets = zeros(0, 1);
    phases = zeros(0, 1);
    if mod(inputFrameBits, inputPeriod) == 0
        puncturePhases = 0;
    else
        puncturePhases = 0:inputPeriod-1;
    end

    for pcmInitialState = pcmInitialStates
        encoderInput = localApplyPCM(asmBits, pcmFormat, pcmInitialState);
        encoder = comm.ConvolutionalEncoder('TrellisStructure', trellis);
        mother = logical(encoder(int8(encoderInput)));
        if flipSecondBranch
            mother(2:2:end) = ~mother(2:2:end);
        end

        for puncturePhase = puncturePhases
            patternIndex = mod(2*puncturePhase + (0:numel(mother)-1), ...
                numel(puncturePattern)) + 1;
            keep = logical(puncturePattern(patternIndex));
            knownMother = false(size(mother));
            knownMother(13:end) = true; % constraint length 7 -> memory 6
            template = mother(keep & knownMother);
            prefixLength = nnz(keep(1:min(12, numel(keep))));

            templates{end+1,1} = template(:); %#ok<AGROW>
            offsets(end+1,1) = prefixLength; %#ok<AGROW>
            phases(end+1,1) = puncturePhase; %#ok<AGROW>
        end
    end

    cfg.asmTemplateCells = templates;
    cfg.asmOffsetBitsByTemplate = offsets;
    cfg.asmTemplatePuncturePhase = phases;
    cfg.framePeriodBits = inputFrameBits / rateValue;
    cfg.periodToleranceBits = max(2, inputPeriod);

    lengths = cellfun(@numel, templates);
    if all(lengths == lengths(1)) && all(offsets == offsets(1))
        cfg.asmTemplates = false(lengths(1), numel(templates));
        for k = 1:numel(templates)
            cfg.asmTemplates(:,k) = templates{k};
        end
        cfg.asmOffsetBits = offsets(1);
    else
        cfg.asmTemplates = [];
        cfg.asmOffsetBits = [];
    end
end

function value = localPositiveIntegerField(s, name)
    if ~isfield(s, name) || isempty(s.(name)) || ...
            ~isnumeric(s.(name)) || ~isscalar(s.(name)) || ...
            ~isfinite(double(s.(name))) || double(s.(name)) <= 0 || ...
            mod(double(s.(name)), 1) ~= 0
        error('gmsk_frame_reset_asm_config:InformationBlockLength', ...
            '%s must be a positive integer.', name);
    end
    value = double(s.(name));
end

function value = localLogicalField(s, name, defaultValue)
    if isfield(s, name) && ~isempty(s.(name))
        value = logical(s.(name));
    else
        value = logical(defaultValue);
    end
    if ~isscalar(value)
        error('gmsk_frame_reset_asm_config:LogicalField', ...
            '%s must be a logical scalar.', name);
    end
end

function localValidateRSConfiguration(messageLength, interleavingDepth, ...
        shortenedMessageLength)
    if ~any(messageLength == [223 239])
        error('gmsk_frame_reset_asm_config:RSConfiguration', ...
            'RSMessageLength must be 223 or 239 bytes.');
    end
    if ~any(interleavingDepth == [1 2 3 4 5 8])
        error('gmsk_frame_reset_asm_config:RSConfiguration', ...
            'RSInterleavingDepth must be 1, 2, 3, 4, 5, or 8.');
    end
    if shortenedMessageLength > messageLength
        error('gmsk_frame_reset_asm_config:RSConfiguration', ...
            ['RSShortenedMessageLength=%d cannot exceed ', ...
             'RSMessageLength=%d.'], ...
            shortenedMessageLength, messageLength);
    end
end

function codewordBits = localLDPCCodewordLength(informationBits, codeRate)
    rateKey = char(string(codeRate));
    if informationBits == 7136
        if ~strcmp(rateKey, '7/8')
            error('gmsk_frame_reset_asm_config:LDPCConfiguration', ...
                'LDPC k=7136 requires CodeRate="7/8".');
        end
        % CCSDS rate 7/8 is exactly the (8160,7136) code (223/255).
        codewordBits = 8160;
        return;
    end

    if ~any(informationBits == [1024 4096 16384])
        error('gmsk_frame_reset_asm_config:LDPCConfiguration', ...
            'Unsupported ordinary TM LDPC information length k=%d.', ...
            informationBits);
    end

    switch rateKey
        case '1/2'
            inverseRate = 2;
        case '2/3'
            inverseRate = 3/2;
        case '4/5'
            inverseRate = 5/4;
        otherwise
            error('gmsk_frame_reset_asm_config:LDPCConfiguration', ...
                ['Ordinary TM LDPC k=%d supports CodeRate ', ...
                 '"1/2", "2/3", or "4/5".'], informationBits);
    end
    codewordBits = round(informationBits * inverseRate);
end

function codewordBits = localTurboCodewordLength(informationBits, codeRate)
    if ~any(informationBits == [1784 3568 7136 8920])
        error('gmsk_frame_reset_asm_config:TurboConfiguration', ...
            'Unsupported CCSDS Turbo information length k=%d.', ...
            informationBits);
    end

    switch char(string(codeRate))
        case '1/2'
            inverseRate = 2;
        case '1/3'
            inverseRate = 3;
        case '1/4'
            inverseRate = 4;
        case '1/6'
            inverseRate = 6;
        otherwise
            error('gmsk_frame_reset_asm_config:TurboConfiguration', ...
                ['Turbo supports CodeRate "1/2", "1/3", ', ...
                 '"1/4", or "1/6".']);
    end

    % Each terminated constituent encoder contributes four tail inputs.
    codewordBits = inverseRate * (informationBits + 4);
end

function output = localApplyPCM(bits, pcmFormat, initialState)
    bits = logical(bits(:));
    if ~any(strcmp(pcmFormat, ["NRZ-M","NRZ-S"]))
        output = bits;
        return;
    end

    output = false(size(bits));
    state = logical(initialState);
    for k = 1:numel(bits)
        inputBit = bits(k);
        if strcmp(pcmFormat, "NRZ-S")
            inputBit = ~inputBit;
        end
        state = xor(state, inputBit);
        output(k) = state;
    end
end

function [rateValue, pattern, flipSecondBranch] = localRateConfiguration(codeRate)
    flipSecondBranch = false;
    switch char(string(codeRate))
        case '1/2'
            rateValue = 1/2;
            pattern = [1;1];
            flipSecondBranch = true;
        case '2/3'
            rateValue = 2/3;
            pattern = [1;1;0;1];
        case '3/4'
            rateValue = 3/4;
            pattern = [1;1;0;1;1;0];
        case '5/6'
            rateValue = 5/6;
            pattern = [1;1;0;1;1;0;0;1;1;0];
        case '7/8'
            rateValue = 7/8;
            pattern = [1;1;0;1;0;1;0;1;1;0;0;1;1;0];
        otherwise
            error('gmsk_frame_reset_asm_config:CodeRate', ...
                'Unsupported convolutional code rate: %s', char(string(codeRate)));
    end
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

function bits = localStandardASM(channelCoding, codeRate)
    codeKey = lower(string(channelCoding));
    rateKey = char(string(codeRate));

    % CCSDS assigns longer attached sync markers to ordinary LDPC and
    % Turbo rates.  These markers are still raw (outside the codeword).
    if codeKey == "ldpc" || codeKey == "turbo"
        switch rateKey
            case {'1/2','2/3','4/5'}
                hexValue = '034776C7272895B0';
            case '1/3'
                hexValue = '25D5C0CE8990F6C9461BF79C';
            case '1/4'
                hexValue = '034776C7272895B0FCB88938D8D76A4F';
            case '1/6'
                hexValue = '25D5C0CE8990F6C9461BF79CDA2A3F31766F0936B9E40863';
            otherwise % Ordinary LDPC 7/8 and the legacy default.
                hexValue = '1ACFFC1D';
        end
    else
        hexValue = '1ACFFC1D';
    end
    bits = localHexToBits(hexValue);
end
