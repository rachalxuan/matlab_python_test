function bitsOut = fourD8PSKTCMViterbiDemod(sym, rEff)
% fourD8PSKTCMViterbiDemod
% 第一版 4D-8PSK-TCM Viterbi demapper
% 目前只支持 ModulationEfficiency = 2
%
% 输入:
%   sym  : 4D-8PSK-TCM 调制后的 8PSK 符号流，每 4 个符号一组
%   rEff : ModulationEfficiency，目前只支持 2
%
% 输出:
%   bitsOut : Viterbi 回溯得到的输入 bit 序列

    sym = sym(:);

%     if rEff ~= 2
%         error('First version only supports ModulationEfficiency = 2.');
%     end
    supportedEffs = [2 2.25 2.5 2.75];

    if ~any(abs(double(rEff) - supportedEffs) < 1e-9)
        error('Unsupported ModulationEfficiency = %g.', rEff);
    end
    
    nBits = round(4 * double(rEff));

%     nBits = round(4 * rEff);   % rEff=2 -> 8 bits/group
    nStates = 512;             % 6-bit conv state + 3-bit diff state
    nWords = 2^nBits;          % 256
    nGroups = floor(length(sym) / 4);

    sym = sym(1:4*nGroups);

    fprintf('[4D Viterbi] rEff=%.2f, symLen=%d, nGroups=%d, nStates=%d, nWords=%d\n', ...
        rEff, length(sym), nGroups, nStates, nWords);

    pskmodSymbols = [ ...
        1+0j; ...
        (1+1j)/sqrt(2); ...
        0+1j; ...
        (-1+1j)/sqrt(2); ...
        -1+0j; ...
        (-1-1j)/sqrt(2); ...
        0-1j; ...
        (1-1j)/sqrt(2)];

    % 初始状态：发送端 4D-TCM state 默认全 0
    initConv = zeros(6, 1, 'int8');
    initDiff = zeros(3, 1, 'int8');
    initState = tcmStateToId(initConv, initDiff);

    infMetric = 1e30;
    pathMetric = infMetric * ones(nStates, 1);
    pathMetric(initState) = 0;

    survivorPrev = zeros(nGroups, nStates, 'uint16');
    survivorWord = zeros(nGroups, nStates, 'uint16');

    % 预生成所有候选输入 bit
    wordBits = zeros(nBits, nWords, 'int8');
    for w = 0:nWords-1
        wordBits(:, w+1) = int8(de2bi(w, nBits, 'left-msb').');
    end

    for ig = 1:nGroups
        if mod(ig, 10) == 0 || ig == 1 || ig == nGroups
            fprintf('[4D Viterbi] group %d / %d\n', ig, nGroups);
        end

        rx4 = sym((ig-1)*4 + 1:ig*4);

        newMetric = infMetric * ones(nStates, 1);
        newPrev = zeros(nStates, 1, 'uint16');
        newWord = zeros(nStates, 1, 'uint16');

        for oldState = 1:nStates
            oldMetric = pathMetric(oldState);

            if oldMetric >= infMetric/2
                continue;
            end

            [oldConv, oldDiff] = tcmIdToState(oldState);

            for w = 0:nWords-1
                candBits = wordBits(:, w+1);

                [candSym, nextConv, nextDiff] = fourD8PSKTCMMapGroup( ...
                    candBits, rEff, oldConv, oldDiff, pskmodSymbols);

                nextState = tcmStateToId(nextConv, nextDiff);

                branchMetric = sum(abs(rx4 - candSym).^2);
                metric = oldMetric + branchMetric;

                if metric < newMetric(nextState)
                    newMetric(nextState) = metric;
                    newPrev(nextState) = uint16(oldState);
                    newWord(nextState) = uint16(w);
                end
            end
        end

        pathMetric = newMetric;
        survivorPrev(ig, :) = newPrev;
        survivorWord(ig, :) = newWord;
    end

    [bestMetric, bestState] = min(pathMetric);
    fprintf('[4D Viterbi] bestMetric = %.6g, bestState = %d\n', bestMetric, bestState);

    % 回溯
    outWords = zeros(nGroups, 1, 'uint16');
    state = bestState;

    for ig = nGroups:-1:1
        outWords(ig) = survivorWord(ig, state);
        prevState = double(survivorPrev(ig, state));

        if prevState == 0
            warning('[4D Viterbi] traceback broken at group %d. Forced to initState.', ig);
            prevState = initState;
        end

        state = prevState;
    end

    bitsOut = zeros(nGroups*nBits, 1, 'int8');

    for ig = 1:nGroups
        w = double(outWords(ig));
        bitsOut((ig-1)*nBits+1:ig*nBits) = int8(de2bi(w, nBits, 'left-msb').');
    end
end

function stateId = tcmStateToId(convState, diffState)
    s = [convState(:); diffState(:)];
    s = double(s(:) ~= 0);

    stateId = 0;
    for k = 1:numel(s)
        stateId = stateId * 2 + s(k);
    end

    stateId = stateId + 1;
end

function [convState, diffState] = tcmIdToState(stateId)
    v = stateId - 1;

    bits = zeros(9, 1, 'int8');
    for k = 9:-1:1
        bits(k) = int8(mod(v, 2));
        v = floor(v / 2);
    end

    convState = bits(1:6);
    diffState = bits(7:9);
end

function [modSym, convState, diffState] = fourD8PSKTCMMapGroup(bits, rEff, convState, diffState, pskmodSymbols)
    switch rEff
        case 2
            diffInd = [1; 5; 8];
        case 2.25
            diffInd = [2; 6; 9];
        case 2.5
            diffInd = [3; 7; 10];
        case 2.75
            diffInd = [4; 8; 11];
        otherwise
            error('Unsupported 4D-8PSK-TCM modulation efficiency: %g', rEff);
    end

    dataIn = int8(bits(:));

    [diffBits, diffState] = fourD8PSKTCMDifferentialCoder(dataIn(diffInd), diffState);
    dataIn(diffInd) = diffBits;

    [xout, convState] = fourD8PSKTrellisEnc(dataIn(1:3), convState);

    symbols = fourD8PSKConstellationMapper([xout; dataIn], rEff);
    modSym = pskmodSymbols(double(symbols) + 1);
end

function [diffOut, diffState] = fourD8PSKTCMDifferentialCoder(diffIn, diffState)
    w = logical(diffIn(:));
    states = logical(diffState(:));
    diffOut = zeros(3, 1, 'int8');

    r0 = and(w(1), states(1));
    r1 = (w(2) & states(2)) | (w(2) & r0) | (states(2) & r0);

    diffOut(1) = int8(xor(w(1), states(1)));
    diffOut(2) = int8(xor(xor(w(2), states(2)), r0));
    diffOut(3) = int8(xor(xor(w(3), states(3)), r1));

    diffState = diffOut;
end

function [xout, convState] = fourD8PSKTrellisEnc(inBits, convState)
    xin = logical(inBits(:));
    states = logical(convState(:));

    xout = int8(states(6));

    states(6) = xor(xor(states(5), xin(1)), logical(xout));
    states(5) = xor(xor(xin(1), xin(2)), states(4));
    states(4) = xor(states(3), xin(3));
    states(3) = xor(states(2), xin(2));
    states(2) = xor(states(1), xin(3));
    states(1) = logical(xout);

    convState = int8(states);
end

function z = fourD8PSKConstellationMapper(x, rEff)
    x = double(x(:));
    z = zeros(4, 1);

    switch rEff
        case 2
            z(1) = (4*x(9)) + (2*x(6)) + x(2);
            z(2) = z(1) + ((4*x(8)) + (2*x(4)));
            z(3) = z(1) + ((4*x(7)) + (2*x(3)));
            z(4) = z(1) + ((4*(x(8)+x(7)+x(5))) + (2*(x(4)+x(3)+x(1))));
        case 2.25
            z(1) = (4*x(10)) + (2*x(7)) + x(3);
            z(2) = z(1) + ((4*x(9)) + (2*x(5)) + x(1));
            z(3) = z(1) + ((4*x(8)) + (2*x(4)));
            z(4) = z(1) + ((4*(x(9)+x(8)+x(6))) + (2*(x(5)+x(4)+x(2))) + x(1));
        case 2.5
            z(1) = (4*x(11)) + (2*x(8)) + x(4);
            z(2) = z(1) + ((4*x(10)) + (2*x(6)) + x(2));
            z(3) = z(1) + ((4*x(9)) + (2*x(5))) + x(1);
            z(4) = z(1) + ((4*(x(10)+x(9)+x(7))) + (2*(x(6)+x(5)+x(3))) + (x(2)+x(1)));
        otherwise
            z(1) = (4*x(12)) + (2*x(9)) + x(5);
            z(2) = z(1) + ((4*x(11)) + 2*x(7) + x(3));
            z(3) = z(1) + ((4*x(10)) + 2*x(6) + x(2));
            z(4) = z(1) + ((4*(x(11)+x(10)+x(8))) + (2*(x(7)+x(6)+x(4))) + (x(3)+x(2)+x(1)));
    end

    z = mod(z, 8);
end