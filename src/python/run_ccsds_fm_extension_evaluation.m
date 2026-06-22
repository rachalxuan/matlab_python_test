function metrics = run_ccsds_fm_extension_evaluation(params)
%RUN_CCSDS_FM_EXTENSION_EVALUATION CCSDS TM + FM extension test chain.
%
% This standalone chain keeps CCSDS TM synchronization/channel coding in
% ccsdsTMWaveformGenerator, maps the encoded bit stream into the FM modem
% structure from FM_SOQPSK/FM_SOQPSK, then decodes the recovered bits with
% HelperCCSDSTMDecoder.
%
% Example:
%   p = struct('symbolRate',20e6,'sps',4,'snr',10,'cfo',2e6, ...
%       'channelCoding','convolutional','ConvolutionalCodeRate','1/2', ...
%       'showFigures',true,'debugFM',true);
%   m = run_ccsds_fm_extension_evaluation(p);

    if nargin < 1 || isempty(params)
        params = struct();
    end
    if ischar(params) || isstring(params)
        opt = jsondecode(char(params));
    else
        opt = params;
    end

    opt = localDefaults(opt);
    tStart = tic;

    [txBits, txInfo] = buildCCSDSTMFMTxBits(opt);
    [txWaveform, fmInfo] = fmModulateBits(txBits, opt);

    [rxWaveform, channelInfo] = applyFMChannelImpairments(txWaveform, opt, txInfo);

    paddingInfo = struct('enabled', false);
    if isfield(opt,'fmAddNoisePadding') && logical(opt.fmAddNoisePadding)
        [rxWaveform, paddingInfo] = addFMNoisePadding(rxWaveform, opt, fmInfo);
    end

    [rxBits, rxSoft, fmRxInfo] = fmDemodulateWaveform(rxWaveform, opt, fmInfo);

    nHard = min(numel(rxBits), numel(txInfo.encodedBits));
    if nHard > 0
        hardErr = nnz(int8(rxBits(1:nHard)) ~= txInfo.encodedBits(1:nHard).');
        hardBER = hardErr / nHard;
    else
        hardErr = 0;
        hardBER = 0.5;
    end

    [decodedBits, lockRate, decInfo] = decodeCCSDSTMBits(rxSoft(:), opt, txInfo);
    [berVal, errCount, bitsCompared, lockRate, frameInfo] = ...
        compareFrameBits(txInfo.validTxFrames, decodedBits, opt.berWarmUpFrames);

    paprDB = 10*log10(max(abs(txWaveform).^2) / mean(abs(txWaveform).^2));

    metrics = struct();
    metrics.success = true;
    metrics.errorMsg = '';
    metrics.info = 'CCSDS TM coding + FM extension';
    metrics.modType = 'FM';
    metrics.channelCoding = char(opt.channelCoding);
    metrics.BER = berVal;
    metrics.ber = berVal;
    metrics.NumErrors = errCount;
    metrics.NumBits = bitsCompared;
    metrics.EncodedHardBER = hardBER;
    metrics.EncodedHardErrors = hardErr;
    metrics.EncodedHardBits = nHard;
    metrics.LockRate = lockRate;
    metrics.FrameLock_pct = 100*lockRate;
    metrics.PAPR_dB = paprDB;
    metrics.Fs = opt.fs;
    metrics.symbolRate = opt.symbolRate;
    metrics.snr_in = opt.snr;
    metrics.cfo_in = opt.cfo;
    metrics.phase_in = opt.phaseOffset;
    metrics.delay_in = opt.delay;
    metrics.TZZS = opt.TZZS;
    metrics.RolloffFactor = opt.RolloffFactor;
    metrics.ElapsedTime = toc(tStart);
    metrics.txInfo = txInfo;
    metrics.fmInfo = fmInfo;
    metrics.fmRxInfo = fmRxInfo;
    metrics.channelInfo = channelInfo;
    metrics.paddingInfo = paddingInfo;
    metrics.decInfo = decInfo;
    metrics.frameInfo = frameInfo;

    if opt.debugFM
        fprintf('   [FM DEBUG] recovered encoded bits = %d/%d\n', nHard, numel(txInfo.encodedBits));
        fprintf('   [FM DEBUG] encoded hard BER = %.6g (%d/%d)\n', hardBER, hardErr, nHard);
        fprintf('   [FM DEBUG] detected FM frames = %d/%d\n', fmRxInfo.detectedFrames, fmInfo.NFrame);
        fprintf('   [FM DEBUG] decoder polarity = %s\n', decInfo.SelectedSoftPolarity);
    end

    printFMResults(metrics);

    if opt.showFigures
        plotFMResults(metrics, txWaveform, rxWaveform, rxSoft);
    end
end

function opt = localDefaults(opt)
    opt = setDefault(opt, 'modType', 'FM');
    opt = setDefault(opt, 'symbolRate', 20e6);
    opt = setDefault(opt, 'sps', 4);
    opt = setDefault(opt, 'fs', []);
    opt = setDefault(opt, 'snr', 10);
    opt = setDefault(opt, 'cfo', 2e6);
    opt = setDefault(opt, 'phaseOffset', 0);
    opt = setDefault(opt, 'delay', 0);
    opt = setDefault(opt, 'channelCoding', 'convolutional');
    opt = setDefault(opt, 'ConvolutionalCodeRate', '1/2');
    opt = setDefault(opt, 'hasASM', true);
    opt = setDefault(opt, 'hasRandomizer', false);
    opt = setDefault(opt, 'NumBytesInTransferFrame', 1115);
    opt = setDefault(opt, 'berWarmUpFrames', 4);
    opt = setDefault(opt, 'berFrames', 20);
    opt = setDefault(opt, 'fmPayloadBitsPerFrame', 10000);
    opt = setDefault(opt, 'RolloffFactor', 0.5);
    opt = setDefault(opt, 'TZZS', 0.715);
    opt = setDefault(opt, 'fmAddNoisePadding', true);
    opt = setDefault(opt, 'showFigures', true);
    opt = setDefault(opt, 'debugFM', true);

    opt.symbolRate = double(opt.symbolRate);
    opt.sps = max(2, round(double(opt.sps)));
    if isempty(opt.fs)
        opt.fs = opt.symbolRate * opt.sps;
    else
        opt.fs = double(opt.fs);
    end
    opt.snr = double(opt.snr);
    opt.cfo = double(opt.cfo);
    opt.phaseOffset = double(opt.phaseOffset);
    opt.delay = double(opt.delay);
    opt.channelCoding = canonicalChannelCodingLocal(opt.channelCoding);
    opt.hasASM = logical(opt.hasASM);
    opt.hasRandomizer = logical(opt.hasRandomizer);
    opt.NumBytesInTransferFrame = double(opt.NumBytesInTransferFrame);
    opt.berWarmUpFrames = max(0, round(double(opt.berWarmUpFrames)));
    opt.berFrames = max(1, round(double(opt.berFrames)));
    opt.fmPayloadBitsPerFrame = max(100, round(double(opt.fmPayloadBitsPerFrame)));
    opt.RolloffFactor = double(opt.RolloffFactor);
    opt.TZZS = double(opt.TZZS);
    opt.fmAddNoisePadding = logical(opt.fmAddNoisePadding);
    opt.showFigures = logical(opt.showFigures);
    opt.debugFM = logical(opt.debugFM);
end

function s = setDefault(s, name, value)
    if ~isfield(s, name) || isempty(s.(name))
        s.(name) = value;
    end
end

function [txBits, infoOut] = buildCCSDSTMFMTxBits(opt)
    args = { ...
        'WaveformSource', 'synchronization and channel coding', ...
        'Modulation', 'BPSK', ...
        'ChannelCoding', opt.channelCoding, ...
        'SamplesPerSymbol', 2, ...
        'HasRandomizer', opt.hasRandomizer, ...
        'HasASM', opt.hasASM};

    codeKey = lower(string(opt.channelCoding));
    if any(strcmp(codeKey, ["none", "convolutional"])) || ...
            (isfield(opt,'IsLDPCOnSMTF') && logical(opt.IsLDPCOnSMTF))
        args = [args, {'NumBytesInTransferFrame', opt.NumBytesInTransferFrame}]; %#ok<AGROW>
    end
    if codeKey == "convolutional" && isfield(opt, 'ConvolutionalCodeRate')
        args = [args, {'ConvolutionalCodeRate', char(opt.ConvolutionalCodeRate)}]; %#ok<AGROW>
    end
    if any(strcmp(codeKey, ["turbo", "ldpc"]))
        if isfield(opt, 'CodeRate')
            args = [args, {'CodeRate', string(opt.CodeRate)}]; %#ok<AGROW>
        end
        if isfield(opt, 'NumBitsInInformationBlock')
            args = [args, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}]; %#ok<AGROW>
        end
    end
    if codeKey == "ldpc" && isfield(opt, 'IsLDPCOnSMTF')
        args = [args, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}]; %#ok<AGROW>
    end
    if codeKey == "ldpc" && isfield(opt, 'LDPCCodeblockSize') && ~isempty(opt.LDPCCodeblockSize)
        args = [args, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}]; %#ok<AGROW>
    end
    args = appendRSArgsLocal(args, opt);

    tmWaveGen = ccsdsTMWaveformGenerator(args{:});
    genInfo = info(tmWaveGen);
    bitsPerFrame = tmWaveGen.NumInputBits;
    totalFrames = opt.berWarmUpFrames + opt.berFrames;
    numHeaderBits = 8;

    msg = zeros(bitsPerFrame * totalFrames, 1, 'int8');
    validTxFrames = cell(totalFrames, 1);
    for iFrame = 1:totalFrames
        header = int8(de2bi(mod(iFrame-1, 256), numHeaderBits, 'left-msb').');
        payload = int8(randi([0 1], bitsPerFrame - numHeaderBits, 1));
        frameBits = [header; payload];
        idx = (iFrame-1)*bitsPerFrame + (1:bitsPerFrame);
        msg(idx) = frameBits;
        validTxFrames{iFrame} = frameBits;
    end

    [~, encodedBits] = tmWaveGen(msg);
    encodedBits = int8(encodedBits(:));

    txBits = encodedBits;
    infoOut = struct();
    infoOut.bitsPerFrame = bitsPerFrame;
    infoOut.validTxFrames = validTxFrames;
    infoOut.encodedBits = encodedBits;
    infoOut.tmWaveGenInfo = genInfo;
end

function [fmWaveform, fmInfo] = fmModulateBits(encodedBits, opt)
    training = loadFMTraining();
    fd = opt.symbolRate;
    fs = opt.fs;
    interN = round(fs / fd);
    if abs(interN - fs/fd) > 1e-9
        error('FM extension requires fs/symbolRate to be an integer. Current fs/symbolRate=%.6g.', fs/fd);
    end

    nPerFrame = opt.fmPayloadBitsPerFrame;
    nFrame = ceil(numel(encodedBits) / nPerFrame);
    padBits = nFrame*nPerFrame - numel(encodedBits);
    if padBits > 0
        encodedBitsPadded = [encodedBits(:); zeros(padBits, 1, 'int8')];
    else
        encodedBitsPadded = encodedBits(:);
    end
    dataSource = reshape(logical(encodedBitsPadded), nPerFrame, nFrame).';

    dataHs = randn(1,100) > 0;
    dataSend = dataHs;
    for ii = 1:nFrame
        dataSend = [dataSend, training, dataSource(ii,:)]; %#ok<AGROW>
    end

    database = double(dataSend)*2 - 1;
    database = upsample(database, interN);
    shapingFilter = rcosine(fd, fs, 'sqrt', opt.RolloffFactor);
    shapingFilter = shapingFilter / sum(shapingFilter);
    dataLPF = conv(database, shapingFilter);

    phaseState = cumsum([0, dataLPF(2:end)]);
    fmWaveform = exp(1j*phaseState*pi*opt.TZZS);
    fmWaveform = fmWaveform(:);

    fmInfo = struct();
    fmInfo.training = logical(training(:).');
    fmInfo.NTraining = numel(training);
    fmInfo.NFrame = nFrame;
    fmInfo.NPerFrame = nPerFrame;
    fmInfo.padBits = padBits;
    fmInfo.encodedBitsPadded = encodedBitsPadded;
    fmInfo.dataSource = dataSource;
    fmInfo.interN = interN;
    fmInfo.dataSend = logical(dataSend);
end

function [rxBits, rxSoft, info] = fmDemodulateWaveform(rxSig, opt, fmInfo)
    fd = opt.symbolRate;
    fs = opt.fs;
    interN = fmInfo.interN;
    nTraining = fmInfo.NTraining;
    training = fmInfo.training;
    fmMatchFilter = double(training)*2 - 1;

    shapingFilter = rcosine(fd, fs, 'sqrt', opt.RolloffFactor);
    shapingFilter = shapingFilter / sum(shapingFilter);
    dataPipeReg = zeros(1, length(shapingFilter));

    bt = 3000*2^10;
    c1 = 8/3*bt;
    c2 = 32/9*bt*bt;
    nSymbols = floor(length(rxSig)/interN);
    nSamples = interN*nSymbols;
    lfOut = [2^30, zeros(1,nSymbols-1)];
    nco = [2^31*0.75, 2^31*0.75, 2^31*0.75, zeros(1,nSamples-3)];
    ncoTemp = [nco(1), zeros(1,nSamples-1)];
    fraSpace = zeros(1,2*nSymbols);
    intet = zeros(1,2*nSymbols);
    timeError = zeros(1,nSymbols);
    interFlag = zeros(1,nSamples);
    dataBaseR = zeros(1,interN);
    nChafen = 1;
    nStop = length(rxSig)-2;

    dataJianceReg = zeros(1,nTraining+10);
    yReg = zeros(1,16);
    dataMix = zeros(1,nStop+4);
    dataBase = zeros(1,nStop+4);
    dataPipe = zeros(1,nStop+4);
    corrComp = zeros(1,21);
    corrVal = zeros(1,nSymbols);
    frameFindFlag = false;
    findDataHead = false;
    cntValid = 1;
    cntFrame = 0;
    output = false(1, fmInfo.NFrame*fmInfo.NPerFrame);
    outputSoft = zeros(1, fmInfo.NFrame*fmInfo.NPerFrame);

    ii = 2;
    k = 1;
    ms = 1;
    p = 1;
    q = 1;
    phase = 0;
    deltPhase = 0;
    mAdapt = 10;
    frameLoc = [];
    findDataLoc = [];
    frameFlagSave = false(1,nSymbols);
    gateSave = zeros(1,nSymbols);

    while ii < nStop
        phase = phase + deltPhase;
        dataMix(ii) = rxSig(ii) * exp(-1j*phase);

        dataBaseR(1:end-1) = dataBaseR(2:end);
        if ii > nChafen
            dataBaseR(end) = angle(dataMix(ii)) - angle(dataMix(ii-nChafen));
        else
            dataBaseR(end) = 0;
        end
        if dataBaseR(end) > pi
            dataBaseR(end) = dataBaseR(end) - 2*pi;
        elseif dataBaseR(end) < -pi
            dataBaseR(end) = dataBaseR(end) + 2*pi;
        end
        dataBase(ii) = sum(dataBaseR(end-interN+1:nChafen:end));

        dataPipeReg = [dataPipeReg(2:end), dataBase(ii)];
        dataPipe(ii+2) = dataPipeReg * shapingFilter';

        ncoTemp(ii+1) = nco(ii) - lfOut(ms);
        if ncoTemp(ii+1) > 0
            nco(ii+1) = ncoTemp(ii+1);
        else
            nco(ii+1) = ncoTemp(ii+1) + 2^31;
            fraSpace(k) = nco(ii) * 2;
            f1 = 0.5*dataPipe(ii+2) - 0.5*dataPipe(ii+1) - 0.5*dataPipe(ii) + 0.5*dataPipe(ii-1);
            f2 = 1.5*dataPipe(ii+1) - 0.5*dataPipe(ii+2) - 0.5*dataPipe(ii) - 0.5*dataPipe(ii-1);
            f3 = dataPipe(ii);
            intet(k) = (f1*fraSpace(k)/(2^31) + f2)*fraSpace(k)/(2^31) + f3;
            interFlag(k) = mod(k,2);

            if interFlag(k) == 0
                if k > 2
                    a = (intet(k) + intet(k-2)) / 2;
                    timeError(ms) = (intet(k-1) - a) * (sign(intet(k)) - sign(intet(k-2)));
                else
                    timeError(ms) = 0;
                end

                if ms > 1
                    lfOut(ms+1) = lfOut(ms) + c1*(timeError(ms)-timeError(ms-1)) + c2*timeError(ms-1);
                    lfOut(ms+1) = 2^30 + c1*timeError(ms);
                else
                    lfOut(ms+1) = 2^30;
                end

                dataJianceReg = [dataJianceReg(2:end), intet(k)];
                corrComp(2*mAdapt+1) = abs((dataJianceReg(end-nTraining+1:end) - ...
                    mean(dataJianceReg(end-nTraining+1:end))) * fmMatchFilter');
                for ss = 1:2*mAdapt
                    corrComp(ss) = corrComp(ss+1);
                end
                gate = opt.TZZS * 100;
                corrVal(ms) = corrComp(mAdapt);
                gateSave(ms) = gate;

                if frameFindFlag
                    q = q + 1;
                    if findDataHead
                        if p > fmInfo.NPerFrame
                            frameFindFlag = false;
                            findDataHead = false;
                            p = 1;
                        elseif cntValid <= numel(output)
                            output(cntValid) = intet(k) > 0;
                            outputSoft(cntValid) = intet(k);
                            p = p + 1;
                            cntValid = cntValid + 1;
                        end
                    else
                        p = 1;
                    end

                    yReg = [yReg(2:end), intet(k) > 0];
                    if sum(abs(yReg - training(end-16+1:end))) == 0 && q < 60
                        findDataHead = true;
                        if cntFrame >= 1
                            findDataLoc(cntFrame) = ms; %#ok<AGROW>
                        end
                    end
                    if q > 60 && ~findDataHead
                        frameFindFlag = false;
                    end
                else
                    findDataHead = false;
                    p = 1;
                    q = 1;
                end

                if corrComp(mAdapt) > gate && ~frameFindFlag
                    deltPhase = deltPhase + mean(dataJianceReg(1:nTraining)) / interN;
                    frameFindFlag = true;
                    ii = ii - (nTraining + mAdapt) * interN;
                    if ii < 4
                        ii = 4;
                    end
                    cntFrame = cntFrame + 1;
                    frameLoc(cntFrame) = ms; %#ok<AGROW>
                    if ii > 0 && ii <= numel(nco)
                        nco(ii) = 0.25*2^31;
                    end
                end

                frameFlagSave(ms) = frameFindFlag;
                ms = ms + 1;
            end
            k = k + 1;
        end
        ii = ii + 1;
    end

    nOut = min(cntValid-1, numel(output));
    rxBits = output(1:nOut);
    rxSoft = outputSoft(1:nOut);

    if fmInfo.padBits > 0 && numel(rxBits) >= fmInfo.padBits
        rxBits = rxBits(1:end-fmInfo.padBits);
        rxSoft = rxSoft(1:end-fmInfo.padBits);
    end

    info = struct();
    info.detectedFrames = cntFrame;
    info.frameLoc = frameLoc;
    info.findDataLoc = findDataLoc;
    info.correlation = corrVal(1:min(ms-1,numel(corrVal)));
    info.gate = gateSave(1:min(ms-1,numel(gateSave)));
    info.frameFlag = frameFlagSave(1:min(ms-1,numel(frameFlagSave)));
    info.dataBase = dataBase;
    info.matched = dataPipe;
end

function training = loadFMTraining()
    fmDir = fullfile(fileparts(mfilename('fullpath')), 'FM_SOQPSK', 'FM_SOQPSK');
    s = load(fullfile(fmDir, 'data_training.mat'), 'data_training');
    training = logical(s.data_training(:).');
end

function [decodedBits, lockRate, decInfo] = decodeCCSDSTMBits(softBits, opt, txInfo)
    softBits = double(softBits(:));
    if isempty(softBits)
        softBits = zeros(0,1);
    end

    softBits = softBits / (sqrt(mean(softBits.^2)) + eps) * 5;
    candidates = {softBits, -softBits};
    candidateNames = {'FM soft', 'inverted FM soft'};

    bestBER = inf;
    bestErr = 0;
    bestBits = 0;
    bestIdx = 1;
    bestDecoded = [];
    bestLock = 0;
    bestFrameInfo = struct();

    for iCandidate = 1:numel(candidates)
        candDecoded = decodeCCSDSTMBitsOnce(candidates{iCandidate}, opt);
        [candBER, candErr, candBits, candLock, candFrameInfo] = ...
            compareFrameBits(txInfo.validTxFrames, candDecoded, opt.berWarmUpFrames);

        if candBER < bestBER || (candBER == bestBER && candLock > bestLock)
            bestBER = candBER;
            bestErr = candErr;
            bestBits = candBits;
            bestIdx = iCandidate;
            bestDecoded = candDecoded;
            bestLock = candLock;
            bestFrameInfo = candFrameInfo;
        end
    end

    decodedBits = bestDecoded;
    lockRate = bestLock;
    decInfo = struct();
    decInfo.SelectedSoftPolarity = candidateNames{bestIdx};
    decInfo.CandidateBER = bestBER;
    decInfo.CandidateErrors = bestErr;
    decInfo.CandidateBits = bestBits;
    decInfo.FrameInfo = bestFrameInfo;
end

function decodedBits = decodeCCSDSTMBitsOnce(softBits, opt)
    decArgs = {'ChannelCoding', opt.channelCoding, ...
        'Modulation', 'BPSK', ...
        'HasRandomizer', opt.hasRandomizer, ...
        'HasASM', opt.hasASM, ...
        'DisablePhaseAmbiguityResolution', true};

    codeKey = lower(string(opt.channelCoding));
    if any(strcmp(codeKey, ["none", "convolutional"])) || ...
            (isfield(opt,'IsLDPCOnSMTF') && logical(opt.IsLDPCOnSMTF))
        decArgs = [decArgs, {'NumBytesInTransferFrame', opt.NumBytesInTransferFrame}]; %#ok<AGROW>
    end
    if isfield(opt, 'ConvolutionalCodeRate')
        decArgs = [decArgs, {'ConvolutionalCodeRate', char(opt.ConvolutionalCodeRate)}]; %#ok<AGROW>
    end
    if isfield(opt, 'CodeRate') && ~strcmp(char(opt.CodeRate), 'N/A')
        decArgs = [decArgs, {'CodeRate', char(opt.CodeRate)}]; %#ok<AGROW>
    end
    if isfield(opt, 'NumBitsInInformationBlock')
        decArgs = [decArgs, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}]; %#ok<AGROW>
    end
    if isfield(opt, 'IsLDPCOnSMTF')
        decArgs = [decArgs, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}]; %#ok<AGROW>
    end
    if isfield(opt, 'LDPCCodeblockSize') && ~isempty(opt.LDPCCodeblockSize)
        decArgs = [decArgs, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}]; %#ok<AGROW>
    end
    decArgs = appendRSArgsLocal(decArgs, opt);

    decoderObj = HelperCCSDSTMDecoder(decArgs{:});
    decodedBits = decoderObj(softBits(:));
end


function [rxWaveform, info] = applyFMChannelImpairments(txWaveform, opt, txInfo)
%APPLYFMCHANNELIMPAIRMENTS 标准信道损伤模块
%
% 统一在这里加入：
%   1. CFO / phase offset
%   2. fractional delay
%   3. AWGN
%
% 这样 FM 调制器只负责“纯调制”，不会在调制器里偷偷加频偏。

    %#ok<INUSD>  % txInfo 当前不用，先保留接口，方便以后扩展

    rxWaveform = txWaveform(:);

    % FM 调制链路的采样率来自 opt.fs
    Fs = opt.fs;

    if opt.cfo ~= 0 || opt.phaseOffset ~= 0
        pfo = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', opt.cfo, ...
            'PhaseOffset', opt.phaseOffset, ...
            'SampleRate', Fs);
        rxWaveform = pfo(rxWaveform);
    end

    if opt.delay ~= 0
        vfd = dsp.VariableFractionalDelay('InterpolationMethod','Farrow');
        rxWaveform = vfd(rxWaveform, opt.delay);
    end

    rxWaveform = awgn(rxWaveform, opt.snr, 'measured');

    info = struct();
    info.Fs = Fs;
    info.cfo_Hz = opt.cfo;
    info.phaseOffset_deg = opt.phaseOffset;
    info.delay_samples = opt.delay;
    info.snr_dB = opt.snr;
end


function [berVal, errCount, bitsCompared, lockRate, frameInfo] = compareFrameBits(validTxFrames, decodedBits, numWarmUp)
    if nargin < 3 || isempty(numWarmUp)
        numWarmUp = 0;
    end

    frameInfo = struct('numRx',0,'framesMatched',0,'firstMatched',NaN, ...
        'perFrameBER',[],'rxIds',[],'matchedMask',[]);

    if isempty(decodedBits) || isempty(validTxFrames)
        berVal = 0.5;
        errCount = 0;
        bitsCompared = 0;
        lockRate = 0;
        return;
    end

    bitsPerFrame = length(validTxFrames{1});
    txMap = containers.Map('KeyType','double','ValueType','any');
    for k = 1:length(validTxFrames)
        fr = int8(validTxFrames{k}(:));
        id = bi2de(double(fr(1:8)).','left-msb');
        txMap(id) = fr;
    end

    decodedBits = int8(decodedBits(:) ~= 0);
    numRx = floor(length(decodedBits) / bitsPerFrame);
    frameInfo.numRx = numRx;
    frameInfo.perFrameBER = nan(1, numRx);
    frameInfo.rxIds = nan(1, numRx);
    frameInfo.matchedMask = false(1, numRx);

    errCount = 0;
    bitsCompared = 0;
    framesMatched = 0;
    hasLastId = false;
    lastRxId = 0;
    consecIdCount = 0;

    for j = 1:numRx
        idx0 = (j-1)*bitsPerFrame + 1;
        rxFr = int8(decodedBits(idx0:idx0+bitsPerFrame-1));
        rxId = bi2de(double(rxFr(1:8)).','left-msb');
        frameInfo.rxIds(j) = rxId;

        if isKey(txMap, rxId)
            framesMatched = framesMatched + 1;
            frameInfo.matchedMask(j) = true;
            txFr = int8(txMap(rxId));
            thisErrs = biterr(double(txFr(:)), double(rxFr(:)));
            frameInfo.perFrameBER(j) = thisErrs / bitsPerFrame;

            if ~hasLastId
                hasLastId = true;
                consecIdCount = 1;
            else
                expectedId = mod(lastRxId + 1, 256);
                if rxId == expectedId
                    consecIdCount = consecIdCount + 1;
                else
                    consecIdCount = 1;
                end
            end
            lastRxId = rxId;

            if consecIdCount > numWarmUp
                errCount = errCount + thisErrs;
                bitsCompared = bitsCompared + bitsPerFrame;
            end
        else
            hasLastId = false;
            consecIdCount = 0;
        end
    end

    frameInfo.framesMatched = framesMatched;
    firstMatched = find(frameInfo.matchedMask, 1, 'first');
    if ~isempty(firstMatched)
        frameInfo.firstMatched = firstMatched;
    end

    if bitsCompared > 0
        berVal = errCount / bitsCompared;
    else
        berVal = 0.5;
    end

    if numRx < 3 || framesMatched == 0
        lockRate = 0;
    elseif ~isempty(firstMatched)
        lockDenom = max(1, numRx - firstMatched + 1);
        lockRate = min(1, sum(frameInfo.matchedMask(firstMatched:end)) / lockDenom);
    else
        lockRate = min(1, framesMatched / numRx);
    end
end

function code = canonicalChannelCodingLocal(value)
    s = lower(strtrim(string(value)));
    if any(strcmp(s, ["none", "no", "uncoded", "n/a"]))
        code = "none";
    elseif any(strcmp(s, ["conv", "convolutional"]))
        code = "convolutional";
    elseif strcmp(s, "rs")
        code = "RS";
    elseif strcmp(s, "concatenated")
        code = "concatenated";
    elseif strcmp(s, "turbo")
        code = "turbo";
    elseif strcmp(s, "ldpc")
        code = "LDPC";
    else
        code = string(value);
    end
end

function args = appendRSArgsLocal(args, opt)
    rsFields = {'RSMessageLength','RSInterleavingDepth', ...
        'IsRSMessageShortened','RSShortenedMessageLength'};
    for i = 1:numel(rsFields)
        f = rsFields{i};
        if isfield(opt, f) && ~isempty(opt.(f))
            args = [args, {f, opt.(f)}]; %#ok<AGROW>
        end
    end
end

function printFMResults(m)
    fprintf('\n========= CCSDS TM + FM 扩展链路结果 =========\n');
    fprintf(' 调制方式 : %s\n', m.modType);
    fprintf(' 编码方式 : %s\n', m.channelCoding);
    fprintf(' 输入 SNR : %.1f dB, fdoppler/CFO=%.1f Hz\n', m.snr_in, m.cfo_in);
    fprintf(' --------------------------------\n');
    fprintf(' BER          : %.6g\n', m.BER);
    fprintf(' Frame Lock   : %6.2f %%\n', 100*m.LockRate);
    fprintf(' Encoded hard BER : %.6g  (%d/%d)\n', ...
        m.EncodedHardBER, m.EncodedHardErrors, m.EncodedHardBits);
    fprintf(' PAPR (Tx)    : %6.2f dB\n', m.PAPR_dB);
    fprintf(' FM frames    : %d detected\n', m.fmRxInfo.detectedFrames);
    fprintf('===============================================\n');
end

function plotFMResults(m, txWaveform, rxWaveform, rxSoft)
    figure('Name','CCSDS TM + FM extension','NumberTitle','off', ...
        'Color',[0.94 0.94 0.94], 'Position',[120 100 1300 430]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile;
    [ptx, f] = periodogram(txWaveform, [], 4096, m.Fs, 'centered');
    [prx, ~] = periodogram(rxWaveform(:), [], 4096, m.Fs, 'centered');
    plot(f/1e6, 10*log10(ptx/max(ptx)), 'b', 'LineWidth',1.2);
    hold on;
    plot(f/1e6, 10*log10(prx/max(prx)), 'r', 'LineWidth',1.0);
    grid on;
    xlabel('频率 (MHz)'); ylabel('归一化 PSD (dB)');
    title('FM 发送/接收频谱');
    legend({'Tx','Rx'}, 'Location','best');

    nexttile;
    c = m.fmRxInfo.correlation;
    g = m.fmRxInfo.gate;
    plot(c, 'b', 'LineWidth',1.0); hold on;
    if ~isempty(g)
        plot(g, 'r--', 'LineWidth',1.0);
    end
    grid on;
    title('训练序列相关检测');
    xlabel('符号索引'); ylabel('相关值');
    legend({'相关峰值','门限'}, 'Location','best');

    nexttile;
    nShow = min(3000, numel(rxSoft));
    plot(rxSoft(1:nShow), '.-', 'Color',[0 0.28 0.65], 'MarkerSize',4);
    grid on;
    xlabel('bit 索引'); ylabel('FM 判决软值');
    title(sprintf('解调软值 | hard BER %.3g', m.EncodedHardBER));
end


function [rxWaveformPad, info] = addFMNoisePadding(rxWaveform, opt, fmInfo)
%ADDFMNOISEPADDING 在接收波形前后补纯噪声，用于模拟接收机捕获前后的空噪声区
%
% 说明：
%   这不是主要信道损伤。
%   主要信道损伤已经在 applyFMChannelImpairments() 中完成：
%       CFO / phase / delay / AWGN
%
%   这里补噪声只是为了让 FM 解调器不能默认第一个采样点就是有效信号，
%   需要靠 training 相关检测自己找到 payload 起点。

    rxWaveform = rxWaveform(:);

    if isempty(rxWaveform)
        rxWaveformPad = rxWaveform;
        info = struct();
        info.enabled = true;
        info.preSamples = 0;
        info.postSamples = 0;
        info.noiseStd = 0;
        return;
    end

    % 每符号采样点数
    if isfield(fmInfo,'SamplesPerSymbol') && ~isempty(fmInfo.SamplesPerSymbol)
        interN = round(double(fmInfo.SamplesPerSymbol));
    elseif isfield(fmInfo,'interN') && ~isempty(fmInfo.interN)
        interN = round(double(fmInfo.interN));
    elseif isfield(opt,'sps') && ~isempty(opt.sps)
        interN = round(double(opt.sps));
    else
        interN = round(double(opt.fs) / double(opt.symbolRate));
    end
    interN = max(interN, 1);

    % 前后补多少个符号长度的噪声
    preNoiseSymbols = 30;
    if isfield(opt,'fmPreNoiseSymbols') && ~isempty(opt.fmPreNoiseSymbols)
        preNoiseSymbols = double(opt.fmPreNoiseSymbols);
    end

    postNoiseSymbols = 1;
    if isfield(opt,'fmPostNoiseSymbols') && ~isempty(opt.fmPostNoiseSymbols)
        postNoiseSymbols = double(opt.fmPostNoiseSymbols);
    end

    nPre  = max(0, round(preNoiseSymbols  * interN));
    nPost = max(0, round(postNoiseSymbols * interN));

    % 根据当前接收信号功率和输入 SNR 估算 padding 噪声功率。
    % 注意：这里不再用 txWaveform 做差估计噪声幅度，避免“已知发送端波形”的仿真假设。
    sigPwr = mean(abs(rxWaveform).^2);

    if isfield(opt,'snr') && isfinite(double(opt.snr))
        noisePwr = sigPwr / (10^(double(opt.snr)/10));
    else
        noisePwr = sigPwr * 1e-3;
    end

    % 复基带噪声：I/Q 两路各分一半功率
    noiseStd = sqrt(noisePwr/2);

    preNoise  = noiseStd * (randn(nPre,1)  + 1j*randn(nPre,1));
    postNoise = noiseStd * (randn(nPost,1) + 1j*randn(nPost,1));

    rxWaveformPad = [preNoise; rxWaveform; postNoise];

    info = struct();
    info.enabled = true;
    info.preSamples = nPre;
    info.postSamples = nPost;
    info.noiseStd = noiseStd;
    info.SamplesPerSymbol = interN;
end


