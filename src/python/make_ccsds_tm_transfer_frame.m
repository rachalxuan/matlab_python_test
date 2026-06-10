function [frameBits, frameBytes, fields] = make_ccsds_tm_transfer_frame(payload, opt)
%MAKE_CCSDS_TM_TRANSFER_FRAME Build a CCSDS TM Transfer Frame.
%
%   [frameBits, frameBytes, fields] = make_ccsds_tm_transfer_frame(payload, opt)
%   creates one TM Transfer Frame following the CCSDS 132.0-B primary frame
%   structure. The output frameBits are MSB-first column bits and frameBytes
%   are uint8 row bytes.
%
%   Minimal example:
%       opt = struct('FrameLengthBytes',1115,'SpacecraftID',1, ...
%                    'VirtualChannelID',0,'HasFECF',true);
%       payload = uint8(randi([0 255], 1, 1000));
%       [bits, bytes, info] = make_ccsds_tm_transfer_frame(payload, opt);
%
%   Common options:
%       FrameLengthBytes / NumBytesInTransferFrame  Total TM frame length.
%       SpacecraftID                              10-bit SCID.
%       VirtualChannelID                         3-bit VCID.
%       MasterChannelFrameCount                  8-bit counter.
%       VirtualChannelFrameCount                 8-bit counter.
%       HasOCF                                   Add 4-octet OCF.
%       OCF                                      4 uint8 octets.
%       HasFECF                                  Add 2-octet FECF.
%       SecondaryHeader                          Optional TFSH bytes.
%       FirstHeaderPointer                       0..2047, default inferred.
%       PayloadIsBits                            Interpret payload as bits.
%       IdleFillByte                             Fill byte, default 0x55.
%       AllowTruncate                            Truncate oversized payload.

    if nargin < 1 || isempty(payload)
        payload = uint8([]);
    end
    if nargin < 2 || isempty(opt)
        opt = struct();
    end

    frameLengthBytes = getOpt(opt, 'FrameLengthBytes', []);
    if isempty(frameLengthBytes)
        frameLengthBytes = getOpt(opt, 'NumBytesInTransferFrame', 1115);
    end

    versionNumber = getOpt(opt, 'TransferFrameVersionNumber', 0);
    spacecraftID = getOpt(opt, 'SpacecraftID', 1);
    virtualChannelID = getOpt(opt, 'VirtualChannelID', 0);
    hasOCF = logical(getOpt(opt, 'HasOCF', false));
    mcFrameCount = getOpt(opt, 'MasterChannelFrameCount', 0);
    vcFrameCount = getOpt(opt, 'VirtualChannelFrameCount', 0);
    syncFlag = getOpt(opt, 'SynchronizationFlag', 0);
    packetOrderFlag = getOpt(opt, 'PacketOrderFlag', 0);
    segmentLengthID = getOpt(opt, 'SegmentLengthID', []);
    firstHeaderPointer = getOpt(opt, 'FirstHeaderPointer', []);
    secondaryHeader = uint8(getOpt(opt, 'SecondaryHeader', uint8([])));
    hasSecondaryHeader = logical(getOpt(opt, 'HasSecondaryHeader', ~isempty(secondaryHeader)));
    hasFECF = logical(getOpt(opt, 'HasFECF', false));
    idleFillByte = uint8(getOpt(opt, 'IdleFillByte', hex2dec('55')));
    allowTruncate = logical(getOpt(opt, 'AllowTruncate', false));
    payloadIsBits = logical(getOpt(opt, 'PayloadIsBits', isa(payload, 'logical')));

    validateInteger('FrameLengthBytes', frameLengthBytes, 8, 65535);
    validateInteger('TransferFrameVersionNumber', versionNumber, 0, 3);
    validateInteger('SpacecraftID', spacecraftID, 0, 1023);
    validateInteger('VirtualChannelID', virtualChannelID, 0, 7);
    validateInteger('MasterChannelFrameCount', mcFrameCount, 0, 255);
    validateInteger('VirtualChannelFrameCount', vcFrameCount, 0, 255);
    validateInteger('SynchronizationFlag', syncFlag, 0, 1);
    validateInteger('PacketOrderFlag', packetOrderFlag, 0, 1);

    if isempty(segmentLengthID)
        if syncFlag == 0
            segmentLengthID = 3;       % CCSDS 132.0-B: set to '11' for packets/idle data.
        else
            segmentLengthID = 0;
        end
    end
    validateInteger('SegmentLengthID', segmentLengthID, 0, 3);

    if hasSecondaryHeader && isempty(secondaryHeader)
        error('make_ccsds_tm_transfer_frame:MissingSecondaryHeader', ...
            'HasSecondaryHeader is true, but SecondaryHeader is empty.');
    end
    if numel(secondaryHeader) > 64
        error('make_ccsds_tm_transfer_frame:SecondaryHeaderTooLong', ...
            'SecondaryHeader must be no longer than 64 octets.');
    end

    if hasOCF
        ocf = uint8(getOpt(opt, 'OCF', zeros(1, 4, 'uint8')));
        if numel(ocf) ~= 4
            error('make_ccsds_tm_transfer_frame:InvalidOCF', 'OCF must contain exactly 4 octets.');
        end
        ocf = reshape(ocf, 1, []);
    else
        ocf = uint8([]);
    end

    primaryHeaderLength = 6;
    secondaryHeaderLength = numel(secondaryHeader);
    ocfLength = numel(ocf);
    fecfLength = 2 * double(hasFECF);
    dataFieldLength = frameLengthBytes - primaryHeaderLength - secondaryHeaderLength - ocfLength - fecfLength;

    if dataFieldLength < 0
        error('make_ccsds_tm_transfer_frame:FrameTooShort', ...
            'FrameLengthBytes is too short for the selected header/OCF/FECF fields.');
    end

    [payloadBytes, payloadPadBits] = normalizePayload(payload, payloadIsBits);
    if numel(payloadBytes) > dataFieldLength
        if allowTruncate
            payloadBytes = payloadBytes(1:dataFieldLength);
        else
            error('make_ccsds_tm_transfer_frame:PayloadTooLong', ...
                'Payload has %d octets, but the Transfer Frame Data Field holds %d octets.', ...
                numel(payloadBytes), dataFieldLength);
        end
    end

    fillLength = dataFieldLength - numel(payloadBytes);
    dataField = [payloadBytes, repmat(idleFillByte, 1, fillLength)];

    if isempty(firstHeaderPointer)
        if isempty(payloadBytes)
            firstHeaderPointer = 2046; % '11111111110': only Idle Data in the data field.
        else
            firstHeaderPointer = 0;    % First packet starts at data-field octet 0.
        end
    end
    validateInteger('FirstHeaderPointer', firstHeaderPointer, 0, 2047);

    primaryHeader = buildPrimaryHeader( ...
        versionNumber, spacecraftID, virtualChannelID, hasOCF, ...
        mcFrameCount, vcFrameCount, hasSecondaryHeader, syncFlag, ...
        packetOrderFlag, segmentLengthID, firstHeaderPointer);

    frameNoFECF = [primaryHeader, reshape(secondaryHeader, 1, []), dataField, ocf];
    if hasFECF
        fecfBytes = crc16ccsdsBytes(bytesToBitsMSB(frameNoFECF));
        frameBytes = [frameNoFECF, fecfBytes];
    else
        fecfBytes = uint8([]);
        frameBytes = frameNoFECF;
    end

    frameBytes = uint8(frameBytes);
    frameBits = bytesToBitsMSB(frameBytes);

    fields = struct();
    fields.FrameLengthBytes = frameLengthBytes;
    fields.PrimaryHeaderLengthBytes = primaryHeaderLength;
    fields.SecondaryHeaderLengthBytes = secondaryHeaderLength;
    fields.TransferFrameDataFieldLengthBytes = dataFieldLength;
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
    fields.PayloadBytesInserted = numel(payloadBytes);
    fields.PayloadPadBits = payloadPadBits;
    fields.IdleFillBytesInserted = fillLength;
    fields.FECF = fecfBytes;
end

function primaryHeader = buildPrimaryHeader(versionNumber, spacecraftID, virtualChannelID, hasOCF, ...
        mcFrameCount, vcFrameCount, hasSecondaryHeader, syncFlag, packetOrderFlag, ...
        segmentLengthID, firstHeaderPointer)

    b = [ ...
        uintToBitsMSB(versionNumber, 2), ...
        uintToBitsMSB(spacecraftID, 10), ...
        uintToBitsMSB(virtualChannelID, 3), ...
        uint8(hasOCF), ...
        uintToBitsMSB(mcFrameCount, 8), ...
        uintToBitsMSB(vcFrameCount, 8), ...
        uint8(hasSecondaryHeader), ...
        uint8(syncFlag), ...
        uint8(packetOrderFlag), ...
        uintToBitsMSB(segmentLengthID, 2), ...
        uintToBitsMSB(firstHeaderPointer, 11)];

    primaryHeader = bitsToBytesMSB(b);
end

function [payloadBytes, payloadPadBits] = normalizePayload(payload, payloadIsBits)
    if isempty(payload)
        payloadBytes = uint8([]);
        payloadPadBits = 0;
        return;
    end

    if payloadIsBits
        bits = uint8(payload(:).' ~= 0);
        payloadPadBits = mod(8 - mod(numel(bits), 8), 8);
        if payloadPadBits > 0
            bits = [bits, zeros(1, payloadPadBits, 'uint8')];
        end
        payloadBytes = bitsToBytesMSB(bits);
    else
        validateattributes(payload, {'numeric', 'logical'}, {'vector'}, mfilename, 'payload', 1);
        payloadBytes = uint8(payload(:).');
        payloadPadBits = 0;
    end
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
        error('make_ccsds_tm_transfer_frame:BitLengthNotOctetAligned', ...
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
        error('make_ccsds_tm_transfer_frame:InvalidOption', ...
            '%s must be an integer in [%d, %d].', name, minValue, maxValue);
    end
end
