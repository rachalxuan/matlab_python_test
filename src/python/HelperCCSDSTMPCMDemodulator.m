classdef HelperCCSDSTMPCMDemodulator
    % HelperCCSDSTMPCMDemodulator  CCSDS PCM 相位调制专用解调器。
    %
    % 这个 helper 故意和普通星座解调器分开:
    % PCM/PM 类波形不是普通 PSK 星座, 需要先做相位检波, 再按符号积分判决。
    % 普通 PSK/APSK 则走星座同步和星座判决链路。

    methods(Static)
        function tf = supports(modulation)
            modStr = string(modulation);
            tf = any(strcmp(modStr, ["PCM/PSK/PM","PCM/PM/biphase-L"]));
        end

        function [softBits, phaseMetric] = demodulate(modulation, rx, opt, Fs, fSym, sps)
            modStr = string(modulation);
            if strcmp(modStr, "PCM/PSK/PM")
                [softBits, phaseMetric] = HelperCCSDSTMPCMDemodulator.pcmPSKPM(rx, opt, Fs, fSym, sps);
            elseif strcmp(modStr, "PCM/PM/biphase-L")
                [softBits, phaseMetric] = HelperCCSDSTMPCMDemodulator.pcmPMBiphaseL(rx, opt, sps);
            else
                error('HelperCCSDSTMPCMDemodulator:UnsupportedModulation', ...
                    'Unsupported PCM modulation: %s', modStr);
            end
        end
    end

    methods(Static, Access = private)
        function [softBits, phaseMetric] = pcmPSKPM(rx, opt, Fs, fSym, sps)
            % PCM/PSK/PM 解调逻辑与 ccsdsTMWaveformGenerator 的发送模型对应。
            % 发送端近似为 waveform = -1j * exp(j * ModulationIndex * NRZL * subcarrier)。
            rx = rx(:);

            modidx = HelperCCSDSTMPCMDemodulator.getf(opt,'ModulationIndex',pi/3);
            subcarrierRatio = HelperCCSDSTMPCMDemodulator.getf(opt,'SubcarrierToSymbolRateRatio',16);
            fc = subcarrierRatio * fSym;

            n = (0:length(rx)-1).';
            t = n / Fs;

            ph = unwrap(angle(1j * rx));
            if abs(HelperCCSDSTMPCMDemodulator.getf(opt,'cfo',0)) > 0
                ph = detrend(ph, 1);
            else
                ph = ph - median(ph);
            end
            pm = ph / (modidx + eps);

            subcarrierWaveform = "sine";
            if isfield(opt,'SubcarrierWaveform') && ~isempty(opt.SubcarrierWaveform)
                subcarrierWaveform = lower(string(opt.SubcarrierWaveform));
            end

            if isfield(opt,'pcmSubcarrierPhaseSearchN') && ~isempty(opt.pcmSubcarrierPhaseSearchN)
                nPhase = max(4, round(double(opt.pcmSubcarrierPhaseSearchN)));
            else
                nPhase = 4;
            end
            phaseGrid = 2*pi*(0:nPhase-1)/nPhase;

            offsetList = HelperCCSDSTMPCMDemodulator.getOffsetList(opt, sps);

            bestMetric = -inf;
            bestSoft = [];
            bestPhaseMetric = [];
            for phi = phaseGrid
                if subcarrierWaveform == "sine"
                    sc = sin(2*pi*fc*t + phi);
                    baseband = 2 * pm .* sc;
                elseif subcarrierWaveform == "square"
                    sc = square(2*pi*fc*t + phi);
                    baseband = pm .* sc;
                else
                    fprintf('   [PCM/PSK/PM warning] unsupported SubcarrierWaveform=%s, use sine.\n', subcarrierWaveform);
                    sc = sin(2*pi*fc*t + phi);
                    baseband = 2 * pm .* sc;
                end

                for off = offsetList
                    seg = baseband(off+1:end);
                    nBits = floor(length(seg) / sps);
                    if nBits < 16
                        continue;
                    end
                    seg = seg(1:nBits*sps);
                    symMat = reshape(seg, sps, nBits);
                    sym = mean(symMat, 1).';
                    sym0 = sym - mean(sym);
                    metric = HelperCCSDSTMPCMDemodulator.twoLevelMetric(sym0);
                    if metric > bestMetric
                        bestMetric = metric;
                        bestSoft = sym;
                        bestPhaseMetric = sym;
                    end
                end
            end

            [softBits, phaseMetric] = HelperCCSDSTMPCMDemodulator.normalizeSoft(bestSoft, bestPhaseMetric);
        end

        function [softBits, phaseMetric] = pcmPMBiphaseL(rx, opt, sps)
            % PCM/PM/biphase-L: 相位检波后按双相码的两个半符号恢复一个 bit。
            rx = rx(:);
            modidx = HelperCCSDSTMPCMDemodulator.getf(opt,'ModulationIndex',pi/3);

            ph = unwrap(angle(1j * rx));
            if abs(HelperCCSDSTMPCMDemodulator.getf(opt,'cfo',0)) > 0
                ph = detrend(ph, 1);
            else
                ph = ph - median(ph);
            end
            chip = ph / (modidx + eps);

            offsetList = HelperCCSDSTMPCMDemodulator.getOffsetList(opt, sps);

            bestMetric = -inf;
            bestSoft = [];
            bestPhaseMetric = [];
            for off = offsetList
                seg = chip(off+1:end);
                nHalf = floor(length(seg) / sps);
                nBits = floor(nHalf / 2);
                if nBits < 16
                    continue;
                end

                seg = seg(1:2*nBits*sps);
                halfMat = reshape(seg, sps, 2*nBits);
                halfSym = mean(halfMat, 1).';
                halfSym = halfSym - median(halfSym);
                pairs = reshape(halfSym, 2, nBits).';

                % lineEncode(bits,'BIPHASE-L',sps): bit 0 -> [- +], bit 1 -> [+ -]。
                sym = 0.5 * (pairs(:,1) - pairs(:,2));
                metric = HelperCCSDSTMPCMDemodulator.twoLevelMetric(sym - mean(sym));
                if metric > bestMetric
                    bestMetric = metric;
                    bestSoft = sym;
                    bestPhaseMetric = halfSym;
                end
            end

            [softBits, phaseMetric] = HelperCCSDSTMPCMDemodulator.normalizeSoft(bestSoft, bestPhaseMetric);
        end

        function offsetList = getOffsetList(opt, sps)
            if isfield(opt,'pcmSampleOffset') && ~isempty(opt.pcmSampleOffset)
                offsetList = double(opt.pcmSampleOffset);
            else
                offsetList = 0:(sps-1);
            end
        end

        function [softBits, phaseMetric] = normalizeSoft(bestSoft, bestPhaseMetric)
            if isempty(bestSoft)
                softBits = zeros(0,1);
                phaseMetric = zeros(0,1);
                return;
            end

            softBits = bestSoft ./ (std(bestSoft) + eps) * 5;
            phaseMetric = bestPhaseMetric(:);
        end

        function metric = twoLevelMetric(x)
            x = x(:);
            pos = x(x >= 0);
            neg = x(x < 0);
            if isempty(pos) || isempty(neg)
                metric = -inf;
            else
                metric = abs(mean(pos) - mean(neg)) / (std(x) + eps);
            end
        end

        function v = getf(s, name, defv)
            if isfield(s,name) && ~isempty(s.(name))
                v = s.(name);
                if ischar(v) || isstring(v)
                    vv = str2double(string(v));
                    if ~isnan(vv)
                        v = vv;
                    end
                end
            else
                v = defv;
            end
        end
    end
end
