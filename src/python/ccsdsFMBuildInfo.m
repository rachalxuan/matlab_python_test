function fmInfo = ccsdsFMBuildInfo(bits, params)
%CCSDSFMBUILDINFO Build FM frame metadata without re-modulating waveform.

    if nargin < 2 || isempty(params)
        params = struct();
    end

    symbolRate = localGet(params, 'symbolRate', 20e6);
    sps = localGet(params, 'sps', 4);
    fs = localGet(params, 'fs', symbolRate * sps);
    rolloff = localGet(params, 'RolloffFactor', 0.5);
    tzzs = localGet(params, 'TZZS', 0.715);

    interN = round(fs / symbolRate);
    if abs(interN - fs/symbolRate) > 1e-9
        error('FM extension requires fs/symbolRate to be an integer. Current fs/symbolRate=%.6g.', fs/symbolRate);
    end

    bits = int8(bits(:) ~= 0);
    nPerFrame = localGet(params, 'fmPayloadBitsPerFrame', numel(bits));
    nPerFrame = max(1, round(double(nPerFrame)));
    nFrame = ceil(numel(bits) / nPerFrame);
    padBits = nFrame*nPerFrame - numel(bits);
    if padBits > 0
        bitsPadded = [bits; zeros(padBits, 1, 'int8')];
    else
        bitsPadded = bits;
    end

    dataSource = reshape(logical(bitsPadded), nPerFrame, nFrame).';
    training = localLoadFMTraining();

    warmupLen = localGet(params, 'fmWarmupBits', 100);
    dataHs = randn(1, max(0, round(double(warmupLen)))) > 0;
    dataSend = dataHs;
    for iFrame = 1:nFrame
        dataSend = [dataSend, training, dataSource(iFrame,:)]; %#ok<AGROW>
    end

    fmInfo = struct();
    fmInfo.training = logical(training(:).');
    fmInfo.NTraining = numel(training);
    fmInfo.NFrame = nFrame;
    fmInfo.NPerFrame = nPerFrame;
    fmInfo.padBits = padBits;
    fmInfo.encodedBitsPadded = bitsPadded;
    fmInfo.dataSource = dataSource;
    fmInfo.interN = interN;
    fmInfo.dataSend = logical(dataSend);
    fmInfo.Fs = fs;
    fmInfo.SymbolRate = symbolRate;
    fmInfo.RolloffFactor = rolloff;
    fmInfo.TZZS = tzzs;
end

function training = localLoadFMTraining()
    fmDir = fullfile(fileparts(mfilename('fullpath')), 'FM_SOQPSK', 'FM_SOQPSK');
    s = load(fullfile(fmDir, 'data_training.mat'), 'data_training');
    training = logical(s.data_training(:).');
end

function value = localGet(s, name, defaultValue)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        raw = s.(name);
        if ischar(raw) || isstring(raw)
            value = str2double(strrep(string(raw), ',', ''));
        else
            value = double(raw);
        end
    else
        value = defaultValue;
    end
end
