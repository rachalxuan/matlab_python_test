function [rxBits, rxSoft, info] = ccsdsFMDemodulateWaveform(rxSig, params, fmInfo)
%CCSDSFMDEMODULATEWAVEFORM Teacher-style FM demodulator wrapper.
%   The output soft values are payload bits extracted after FM training
%   detection. They can be passed directly to HelperCCSDSTMDecoder.

    if nargin < 2 || isempty(params)
        params = struct();
    end
    if nargin < 3 || isempty(fmInfo)
        fmInfo = localDefaultFMInfo(params);
    end

    fd = localGet(params, 'symbolRate', localGet(fmInfo, 'SymbolRate', 20e6));
    fs = localGet(params, 'fs', localGet(fmInfo, 'Fs', fd * localGet(params, 'sps', 4)));
    rolloff = localGet(params, 'RolloffFactor', localGet(fmInfo, 'RolloffFactor', 0.5));
    tzzs = localGet(params, 'TZZS', localGet(fmInfo, 'TZZS', 0.715));

    rxSig = rxSig(:);
    interN = round(localGet(fmInfo, 'interN', fs / fd));
    nTraining = fmInfo.NTraining;
    training = logical(fmInfo.training(:).');
    fmMatchFilter = double(training)*2 - 1;

    shapingFilter = rcosine(fd, fs, 'sqrt', rolloff);
    shapingFilter = shapingFilter / sum(shapingFilter);
    dataPipeReg = zeros(1, length(shapingFilter));

    bt = 3000*2^10;
    c1 = 8/3*bt;
    c2 = 32/9*bt*bt; %#ok<NASGU>
    nSymbols = floor(length(rxSig)/interN);
    nSamples = interN*nSymbols;
    if nSamples < 4 || nSymbols < 2
        rxBits = false(0,1);
        rxSoft = zeros(0,1);
        info = struct('detectedFrames',0,'frameLoc',[],'findDataLoc',[], ...
            'correlation',[],'gate',[],'frameFlag',[],'dataBase',[],'matched',[]);
        return;
    end

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
                gate = tzzs * 100;
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
    rxBits = output(1:nOut).';
    rxSoft = outputSoft(1:nOut).';

    if fmInfo.padBits > 0 && numel(rxBits) >= fmInfo.padBits
        rxBits = rxBits(1:end-fmInfo.padBits);
        rxSoft = rxSoft(1:end-fmInfo.padBits);
    end

    info = struct();
    info.detectedFrames = cntFrame;
    info.totalFrames = fmInfo.NFrame;
    info.frameLoc = frameLoc;
    info.findDataLoc = findDataLoc;
    info.correlation = corrVal(1:min(ms-1,numel(corrVal)));
    info.gate = gateSave(1:min(ms-1,numel(gateSave)));
    info.frameFlag = frameFlagSave(1:min(ms-1,numel(frameFlagSave)));
    info.dataBase = dataBase;
    info.matched = dataPipe;
end

function fmInfo = localDefaultFMInfo(params)
    training = localLoadFMTraining();
    fmInfo = struct();
    fmInfo.training = training;
    fmInfo.NTraining = numel(training);
    fmInfo.NFrame = localGet(params, 'fmNumFrames', 1);
    fmInfo.NPerFrame = localGet(params, 'fmPayloadBitsPerFrame', 10000);
    fmInfo.padBits = localGet(params, 'fmPadBits', 0);
    fmInfo.interN = localGet(params, 'sps', 4);
    fmInfo.SymbolRate = localGet(params, 'symbolRate', 20e6);
    fmInfo.Fs = localGet(params, 'fs', fmInfo.SymbolRate * fmInfo.interN);
    fmInfo.RolloffFactor = localGet(params, 'RolloffFactor', 0.5);
    fmInfo.TZZS = localGet(params, 'TZZS', 0.715);
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
