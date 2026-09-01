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

    receiverMode = lower(string(localGetText( ...
        params,'fmReceiverMode','matched-training')));
    if any(receiverMode == ["matched-training","matched","differential-matched"])
        [rxBits,rxSoft,info] = localMatchedTrainingReceiver( ...
            rxSig,params,fmInfo,fd,fs,rolloff,tzzs);
        return;
    end

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

function value = localGetText(s,name,defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        value = char(string(s.(name)));
    end
end

function [rxBits,rxSoft,info] = localMatchedTrainingReceiver( ...
        rxSig,params,fmInfo,fd,fs,rolloff,tzzs)
% Differential FM discriminator followed by the matched pulse-shaping
% filter.  The known 48-bit FM training word is used only for frame timing
% and polarity; payload samples remain decision directed.
    rxSig = complex(rxSig(:));
    interN = round(localGet(fmInfo,'interN',fs/fd));
    training = double(logical(fmInfo.training(:)))*2-1;
    nTraining = numel(training);
    nFrame = max(0,round(localGet(fmInfo,'NFrame',0)));
    nPerFrame = max(1,round(localGet(fmInfo,'NPerFrame',1)));
    minScore = localGet(params,'fmTrainingMinNormalizedCorrelation',0.65);
    searchRadius = max(1,round(localGet(params,'fmTrainingSearchSymbols',8)));

    if numel(rxSig) < 2 || interN < 1 || nTraining < 1 || nFrame < 1
        rxBits = false(0,1);
        rxSoft = zeros(0,1);
        info = localMatchedTrainingInfo(nFrame);
        return;
    end

    phaseIncrement = [0; angle(rxSig(2:end).*conj(rxSig(1:end-1)))];
    discriminator = phaseIncrement/max(pi*abs(tzzs),eps);
    shapingFilter = rcosine(fd,fs,'sqrt',rolloff);
    shapingFilter = shapingFilter(:)/sum(shapingFilter);
    matched = conv(discriminator,shapingFilter);

    best = struct('Score',-inf,'Phase',1,'Start',1,'Polarity',1, ...
        'Symbols',zeros(0,1),'Correlation',zeros(0,1));
    trainingEnergy = sum(training.^2);
    for phase = 1:interN
        symbols = matched(phase:interN:end);
        if numel(symbols) < nTraining
            continue;
        end
        correlation = conv(symbols,flipud(training),'valid');
        windowEnergy = conv(symbols.^2,ones(nTraining,1),'valid');
        normalized = abs(correlation)./sqrt( ...
            max(windowEnergy*trainingEnergy,eps));
        [score,startIndex] = max(normalized);
        if score > best.Score
            polarity = sign(correlation(startIndex));
            if polarity == 0, polarity = 1; end
            best = struct('Score',score,'Phase',phase, ...
                'Start',startIndex,'Polarity',polarity, ...
                'Symbols',symbols,'Correlation',correlation);
        end
    end

    outputSoft = zeros(nFrame*nPerFrame,1);
    frameLoc = nan(nFrame,1);
    frameScores = nan(nFrame,1);
    accepted = false(nFrame,1);
    framePeriod = nTraining+nPerFrame;
    if isfinite(best.Score) && best.Score >= minScore
        for frameIndex = 1:nFrame
            expected = best.Start+(frameIndex-1)*framePeriod;
            lo = max(1,expected-searchRadius);
            hi = min(numel(best.Correlation),expected+searchRadius);
            if hi < lo
                continue;
            end
            candidate = best.Correlation(lo:hi);
            candidateEnergy = zeros(size(candidate));
            for q = 1:numel(candidate)
                segment = best.Symbols(lo+q-1+(0:nTraining-1));
                candidateEnergy(q) = sum(segment.^2);
            end
            candidateScore = abs(candidate)./sqrt( ...
                max(candidateEnergy*trainingEnergy,eps));
            [frameScore,localIndex] = max(candidateScore);
            startIndex = lo+localIndex-1;
            payloadStart = startIndex+nTraining;
            payloadEnd = payloadStart+nPerFrame-1;
            if frameScore < minScore || payloadEnd > numel(best.Symbols)
                continue;
            end
            polarity = sign(best.Correlation(startIndex));
            if polarity == 0, polarity = best.Polarity; end
            payload = polarity*best.Symbols(payloadStart:payloadEnd);
            outIndex = (frameIndex-1)*nPerFrame+(1:nPerFrame);
            outputSoft(outIndex) = payload;
            frameLoc(frameIndex) = startIndex;
            frameScores(frameIndex) = frameScore;
            accepted(frameIndex) = true;
        end
    end

    outputSoft = reshape(outputSoft,[],1);
    if any(accepted)
        validScale = median(abs(outputSoft(outputSoft ~= 0)));
        if ~isfinite(validScale) || validScale <= eps
            validScale = sqrt(mean(outputSoft.^2)+eps);
        end
        outputSoft = 5*outputSoft/max(validScale,eps);
        outputSoft = max(min(outputSoft,20),-20);
    end
    if fmInfo.padBits > 0 && numel(outputSoft) >= fmInfo.padBits
        outputSoft = outputSoft(1:end-fmInfo.padBits);
    end
    rxSoft = outputSoft;
    rxBits = rxSoft > 0;

    info = localMatchedTrainingInfo(nFrame);
    info.detectedFrames = nnz(accepted);
    info.frameLoc = frameLoc(accepted).';
    info.findDataLoc = info.frameLoc+nTraining;
    info.correlation = frameScores;
    info.gate = repmat(minScore,nFrame,1);
    info.frameFlag = accepted;
    info.dataBase = discriminator;
    info.matched = matched;
    info.receiverMode = 'matched-training';
    info.bestNormalizedCorrelation = best.Score;
    info.selectedSamplePhase = best.Phase;
end

function info = localMatchedTrainingInfo(nFrame)
    info = struct('detectedFrames',0,'totalFrames',nFrame, ...
        'frameLoc',[],'findDataLoc',[],'correlation',[], ...
        'gate',[],'frameFlag',false(nFrame,1),'dataBase',[], ...
        'matched',[],'receiverMode','matched-training', ...
        'bestNormalizedCorrelation',NaN,'selectedSamplePhase',NaN);
end
