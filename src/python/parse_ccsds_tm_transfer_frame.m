function [dataFieldBytes, fields, frameBytes] = parse_ccsds_tm_transfer_frame(frameInput, opt)
%PARSE_CCSDS_TM_TRANSFER_FRAME Parse a CCSDS TM Transfer Frame.
%
%   [dataFieldBytes, fields, frameBytes] = parse_ccsds_tm_transfer_frame(frameInput, opt)
%   parses one CCSDS 132.0-B TM Transfer Frame. frameInput can be either
%   MSB-first bits or uint8 bytes. dataFieldBytes is the Transfer Frame Data
%   Field as uint8 row bytes.
%
%   Important management options:
%       InputIsBits             Interpret frameInput as bits. Default: logical input.
%       HasFECF                 Whether the final 2 octets are FECF. Default: false.
%       SecondaryHeaderLength   TFSH length in octets. Default: 0.
%
%   Minimal example:
%       opt = struct('HasFECF',true);
%       [dataField, info] = parse_ccsds_tm_transfer_frame(frameBits, opt);
%       disp(info.FECFValid)

    if nargin < 1 || isempty(frameInput)
        error('parse_ccsds_tm_transfer_frame:EmptyInput', 'frameInput must not be empty.');
    end
    if nargin < 2 || isempty(opt)
        opt = struct();
    end

    inputIsBitsOpt = getOpt(opt, 'InputIsBits', []);
    if isempty(inputIsBitsOpt)
        inputIsBits = isa(frameInput, 'logical') || all(frameInput(:) == 0 | frameInput(:) == 1);
    else
        inputIsBits = logical(inputIsBitsOpt);
    end
    hasFECF = logical(getOpt(opt, 'HasFECF', false));
    secondaryHeaderLength = getOpt(opt, 'SecondaryHeaderLength', 0);

    validateInteger('SecondaryHeaderLength', secondaryHeaderLength, 0, 64);

    if inputIsBits
        frameBytes = bitsToBytesMSB(uint8(frameInput(:).' ~= 0));
    else
        validateattributes(frameInput, {'numeric', 'logical'}, {'vector'}, mfilename, 'frameInput', 1);
        frameBytes = uint8(frameInput(:).');
    end

    if numel(frameBytes) < 6
        error('parse_ccsds_tm_transfer_frame:FrameTooShort', ...
            'A TM Transfer Frame must contain at least the 6-octet primary header.');
    end

    headerBits = bytesToBitsMSB(frameBytes(1:6));
    k = 1;
    versionNumber = bitsToUint(headerBits(k:k+1)); k = k + 2;
    spacecraftID = bitsToUint(headerBits(k:k+9)); k = k + 10;
    virtualChannelID = bitsToUint(headerBits(k:k+2)); k = k + 3;
    hasOCF = logical(headerBits(k)); k = k + 1;
    mcFrameCount = bitsToUint(headerBits(k:k+7)); k = k + 8;
    vcFrameCount = bitsToUint(headerBits(k:k+7)); k = k + 8;
    hasSecondaryHeader = logical(headerBits(k)); k = k + 1;
    syncFlag = bitsToUint(headerBits(k)); k = k + 1;
    packetOrderFlag = bitsToUint(headerBits(k)); k = k + 1;
    segmentLengthID = bitsToUint(headerBits(k:k+1)); k = k + 2;
    firstHeaderPointer = bitsToUint(headerBits(k:k+10));

    if hasSecondaryHeader && secondaryHeaderLength == 0
        warning('parse_ccsds_tm_transfer_frame:SecondaryHeaderLengthUnknown', ...
            ['The primary header indicates a Transfer Frame Secondary Header, ', ...
             'but SecondaryHeaderLength is 0. Parsing continues with zero secondary-header length.']);
    end

    primaryHeaderLength = 6;
    ocfLength = 4 * double(hasOCF);
    fecfLength = 2 * double(hasFECF);
    dataStart = primaryHeaderLength + secondaryHeaderLength + 1;
    dataEnd = numel(frameBytes) - ocfLength - fecfLength;

    if dataEnd < dataStart - 1
        error('parse_ccsds_tm_transfer_frame:InvalidLengths', ...
            'The selected SecondaryHeaderLength/HasFECF settings are inconsistent with frame length.');
    end

    if secondaryHeaderLength > 0
        secondaryHeader = frameBytes(primaryHeaderLength + (1:secondaryHeaderLength));
    else
        secondaryHeader = uint8([]);
    end

    dataFieldBytes = frameBytes(dataStart:dataEnd);

    if hasOCF
        ocfStart = dataEnd + 1;
        ocfBytes = frameBytes(ocfStart:ocfStart+3);
    else
        ocfBytes = uint8([]);
    end

    if hasFECF
        fecfBytes = frameBytes(end-1:end);
        calcFECF = crc16ccsdsBytes(bytesToBitsMSB(frameBytes(1:end-2)));
        fecfValid = isequal(fecfBytes, calcFECF);
    else
        fecfBytes = uint8([]);
        calcFECF = uint8([]);
        fecfValid = [];
    end

    fields = struct();
    fields.FrameLengthBytes = numel(frameBytes);
    fields.PrimaryHeaderLengthBytes = primaryHeaderLength;
    fields.SecondaryHeaderLengthBytes = secondaryHeaderLength;
    fields.TransferFrameDataFieldLengthBytes = numel(dataFieldBytes);
    fields.OperationalControlFieldLengthBytes = ocfLength;
    fields.FrameErrorControlFieldLengthBytes = fecfLength;
    fields.TransferFrameVersionNumber = versionNumber;
    fields.SpacecraftID = spacecraftID;
    fields.VirtualChannelID = virtualChannelID;
    fields.HasOCF = hasOCF;
    fields.MasterChannelFrameCount = mcFrameCount;
    fields.VirtualChannelFrameCount = vcFrameCount;
    fields.HasSecondaryHeader = hasSecondaryHeader;
    fields.SynchronizationFlag = syncFlag;
    fields.PacketOrderFlag = packetOrderFlag;
    fields.SegmentLengthID = segmentLengthID;
    fields.FirstHeaderPointer = firstHeaderPointer;
    fields.SecondaryHeader = secondaryHeader;
    fields.OCF = ocfBytes;
    fields.FECF = fecfBytes;
    fields.CalculatedFECF = calcFECF;
    fields.FECFValid = fecfValid;
    fields.ContainsOnlyIdleData = syncFlag == 0 && firstHeaderPointer == 2046;
    fields.NoPacketStartsInDataField = syncFlag == 0 && firstHeaderPointer == 2047;
end

function bits = bytesToBitsMSB(bytes)
    bytes = uint8(bytes(:).');
    bits = zeros(numel(bytes) * 8, 1, 'uint8');
    k = 1;
    for i = 1:numel(bytes)
        for b = 7:-1:0
            bits(k) = uint8(bitget(bytes(i), b + 1));
            k = k + 1;
        end
    end
end

function bytes = bitsToBytesMSB(bits)
    bits = uint8(bits(:).' ~= 0);
    if mod(numel(bits), 8) ~= 0
        error('parse_ccsds_tm_transfer_frame:BitLengthNotOctetAligned', ...
            'Bit vector length must be an integer number of octets.');
    end

    bytes = zeros(1, numel(bits) / 8, 'uint8');
    for i = 1:numel(bytes)
        octet = bits((i - 1) * 8 + (1:8));
        value = uint8(0);
        for b = 1:8
            value = bitor(value, bitshift(uint8(octet(b)), 8 - b));
        end
        bytes(i) = value;
    end
end

function value = bitsToUint(bits)
    bits = uint8(bits(:).' ~= 0);
    value = 0;
    for i = 1:numel(bits)
        value = value * 2 + double(bits(i));
    end
end

function bits = uintToBitsMSB(value, nBits)
    bits = zeros(1, nBits, 'uint8');
    value = uint64(value);
    for i = 1:nBits
        bits(i) = uint8(bitget(value, nBits - i + 1));
    end
end

function fecfBytes = crc16ccsdsBytes(bits)
    bits = uint8(bits(:).' ~= 0);
    reg = uint16(hex2dec('FFFF'));
    poly = uint16(hex2dec('1021'));

    for i = 1:numel(bits)
        topBit = bitget(reg, 16);
        reg = bitand(bitshift(reg, 1), uint16(hex2dec('FFFF')));
        if xor(logical(topBit), logical(bits(i)))
            reg = bitxor(reg, poly);
        end
    end

    fecfBits = uintToBitsMSB(reg, 16);
    fecfBytes = bitsToBytesMSB(fecfBits);
end

function value = getOpt(opt, name, defaultValue)
    if isstruct(opt) && isfield(opt, name) && ~isempty(opt.(name))
        value = opt.(name);
    else
        value = defaultValue;
    end
end

function validateInteger(name, value, minValue, maxValue)
    if ~isscalar(value) || value ~= floor(value) || value < minValue || value > maxValue
        error('parse_ccsds_tm_transfer_frame:InvalidOption', ...
            '%s must be an integer in [%d, %d].', name, minValue, maxValue);
    end
end
