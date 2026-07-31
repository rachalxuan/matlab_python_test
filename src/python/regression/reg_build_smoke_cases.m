function cases = reg_build_smoke_cases()
%REG_BUILD_SMOKE_CASES Formal, bounded CCSDS TM smoke catalog.
%
% These cases check branch integrity with fixed seeds and short frame counts.
% They are not substitutes for long BER performance sweeps.

    base = localBaseParams();
    cases = localEmptyCases();

    p = base;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.qpsk.none.single", "QPSK none single", "core", p, ...
        1e-3, 0.80, 0.20, 1);

    p = base;
    p.DataPathMode = 'dualIQ';
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.qpsk.none.dualiq", "QPSK none dualIQ", "data_path", p, ...
        1e-2, 0.70, 0.30, 1);

    p = base;
    p.channelCoding = 'convolutional';
    p.ConvolutionalCodeRate = '1/2';
    p.RandomizerEnabled = true;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.qpsk.conv12.single.random_after", ...
        "QPSK conv1/2 single random after FEC", "randomizer", p, ...
        1e-2, 0.75, 0.30, 1);

    p.DataPathMode = 'dualIQ';
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.qpsk.conv12.dualiq.random_after", ...
        "QPSK conv1/2 dualIQ random after FEC", "data_path", p, ...
        2e-2, 0.65, 0.40, 1);

    p = base;
    p.modType = '8PSK';
    p.channelCoding = 'RS';
    p.RSMessageLength = 223;
    p.RSInterleavingDepth = 1;
    p.IsRSMessageShortened = false;
    p.RandomizerEnabled = true;
    p.RandomizerFECPosition = 'beforeEncoding';
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.8psk.rs.random_before", ...
        "8PSK RS random before FEC", "randomizer", p, ...
        2e-2, 0.70, 0.40, 1);

    p = base;
    p.modType = '8PSK';
    p.channelCoding = 'convolutional';
    p.ConvolutionalCodeRate = '2/3';
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.8psk.conv23", "8PSK convolutional 2/3", "coding", p, ...
        2e-2, 0.70, 0.40, 1);

    p = base;
    p.channelCoding = 'LDPC';
    p.CodeRate = '1/2';
    p.NumBitsInInformationBlock = 1024;
    p.IsLDPCOnSMTF = false;
    p.RandomizerEnabled = true;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.qpsk.ldpc12", "QPSK LDPC 1/2", "coding", p, ...
        2e-2, 0.65, 0.40, 1);

    p = base;
    p.channelCoding = 'turbo';
    p.CodeRate = '1/2';
    p.NumBitsInInformationBlock = 1784;
    p.RandomizerEnabled = true;
    p.RandomizerFECPosition = 'beforeEncoding';
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.qpsk.turbo12", "QPSK turbo 1/2", "coding", p, ...
        2e-2, 0.65, 0.40, 1);

    p = base;
    p.channelCoding = 'TPC';
    p.TPCCodeRate = '56';
    p.TPCBlocksPerTF = 1;
    p.TPCInterleaver = 'auto';
    p.NumBytesInTransferFrame = 392;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.qpsk.tpc56", "QPSK TPC 56x56", "coding", p, ...
        2e-2, 0.65, 0.40, 1);

    p = base;
    p.modType = 'GMSK';
    p.channelCoding = 'convolutional';
    p.ConvolutionalCodeRate = '1/2';
    p.BandwidthTimeProduct = 0.5;
    p.GMSKDetectionMode = 'official-viterbi-frame-reset';
    p.sps = 8;
    p.snr = 20;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.gmsk.conv12.official", ...
        "GMSK conv1/2 official Viterbi", "modulation", p, ...
        2e-2, 0.65, 0.40, 1);

    p = base;
    p.modType = '16QAM';
    p.channelCoding = 'convolutional';
    p.ConvolutionalCodeRate = '1/2';
    p.snr = 25;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.16qam.conv12", "16QAM convolutional 1/2", "modulation", p, ...
        2e-2, 0.65, 0.40, 1);

    p = base;
    p.modType = 'PCM/PSK/PM';
    p.PCMFormat = 'NRZ-L';
    p.SubcarrierWaveform = 'sine';
    p.SubcarrierToSymbolRateRatio = 2;
    p.ModulationIndex = pi/3;
    p.sps = 8;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.pcm.psk.pm", "PCM/PSK/PM", "modulation", p, ...
        2e-2, 0.65, 0.40, 1);

    p = base;
    p.modType = '4D-8PSK-TCM';
    p.ModulationEfficiency = 2.25;
    % Keep (TF bits + 32-bit ASM) divisible by the 9-bit TCM group while
    % using a genuinely short frame.  The previous 1112-byte smoke case
    % exercised the same path but spent about ten minutes in Viterbi.
    p.NumBytesInTransferFrame = 14;
    p.berWarmUpFrames = 2;
    p.berFrames = 3;
    p.tcmSymbolSkip = 0;
    p.tcmBitSkip = 0;
    p.tcmSearchAll = false;
    p.tcmSampleOffsetSearchAll = true;
    p.snr = 25;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.4dtcm.eff225", "4D-8PSK-TCM efficiency 2.25", "modulation", p, ...
        2e-2, 0.65, 0.40, 1);

    p = localAPSKParams(base, '16APSK', 'ordinaryTM');
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.16apsk.ordinarytm", "16APSK ordinary TM", "apsk", p, ...
        5e-2, 0.50, 0.50, 1);

    p = localAPSKParams(base, '32APSK', 'ordinaryTM');
    p.snr = 35;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.32apsk.ordinarytm", "32APSK ordinary TM", "apsk", p, ...
        1e-1, 0.50, 0.60, 1);

    p = localAPSKParams(base, '16APSK', 'FACM');
    p.ACMFormat = 14;
    p.facmWarmupFrames = 1;
    p.facmBERFrames = 3;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.16apsk.facm", "16APSK official FACM", "apsk", p, ...
        1e-1, 0.50, [], []);

    p = base;
    p.enableHChannel = true;
    p.HMode = 'siso_multipath';
    p.H = [1, 0, 0.25*exp(1j*pi/3), 0, 0.10*exp(-1j*pi/4)];
    p.normalizeHChannel = true;
    p.enableEqualizer = false;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.h.mild.noeq", "QPSK mild H without EQ", "h_channel", p, ...
        5e-2, 0.50, 0.60, 1);

    p.H = [1, 0, 0.85*exp(1j*pi/3), 0, ...
        0.60*exp(-1j*pi/4), 0, 0.40*exp(1j*pi/2)];
    p.enableEqualizer = true;
    p.equalizerMode = 'mmse';
    p.normalizeEqualizerOutput = true;
    cases(end+1,1) = localCase( ... %#ok<AGROW>
        "smoke.h.strong.mmse", "QPSK strong H with MMSE EQ", "h_channel", p, ...
        1e-1, 0.50, 0.70, 1);
end

function p = localBaseParams()
    p = struct( ...
        'modType','QPSK', ...
        'symbolRate',1e6, ...
        'sps',4, ...
        'snr',30, ...
        'cfo',2000, ...
        'phaseOffset',10, ...
        'delay',0.2, ...
        'channelCoding','none', ...
        'RolloffFactor',0.35, ...
        'hasASM',true, ...
        'RandomizerEnabled',false, ...
        'RandomizerFECPosition','afterEncoding', ...
        'DataPathMode','single', ...
        'WaveformMode','ordinaryTM', ...
        'NumBytesInTransferFrame',1115, ...
        'berWarmUpFrames',3, ...
        'berFrames',8, ...
        'showFigures',false, ...
        'showPipelineFigure',false, ...
        'showDamageBudgetFigure',false, ...
        'showPowerFigure',false);
end

function p = localAPSKParams(base, modulation, waveformMode)
    p = base;
    p.modType = modulation;
    p.WaveformMode = waveformMode;
    p.sps = 8;
    p.snr = 30;
    p.HasTMAPSKPilots = true;
    p.TMAPSKPilotInterval = 512;
    p.TMAPSKPilotLength = 32;
    p.TMAPSKPilotPreambleLength = 64;
    p.TMAPSKPilotCorrectionMode = 'phaseinterp';
end

function cases = localEmptyCases()
    cases = struct('Id',{},'Name',{},'Category',{}, ...
        'Params',{},'Expected',{},'Meta',{});
end

function caseDef = localCase(id, name, category, params, ...
        maxBER, minLockRate, maxFER, minCountedFrames)
    expectedDetector = "";
    if strcmpi(string(params.modType), "GMSK")
        expectedDetector = "official";
    end
    expected = struct( ...
        'RequiredMetrics', ["BER","LockRate"], ...
        'MaxBER', maxBER, ...
        'MinLockRate', minLockRate, ...
        'MaxFER', maxFER, ...
        'MinMERdB', [], ...
        'MinCountedFrames', minCountedFrames, ...
        'ExpectedDataPathMode', string(params.DataPathMode), ...
        'ExpectedWaveformMode', string(params.WaveformMode), ...
        'ExpectedRandomizerFECPosition', string(params.RandomizerFECPosition), ...
        'ExpectedRandomizerEnabled', logical(params.RandomizerEnabled), ...
        'ExpectedGMSKDetector', expectedDetector, ...
        'ExpectedErrorIdentifier', "", ...
        'ExpectedErrorMessage', "");
    meta = struct( ...
        'Modulation', string(params.modType), ...
        'Coding', string(params.channelCoding), ...
        'DataPathMode', string(params.DataPathMode), ...
        'WaveformMode', string(params.WaveformMode));
    caseDef = struct( ...
        'Id', string(id), ...
        'Name', string(name), ...
        'Category', string(category), ...
        'Params', params, ...
        'Expected', expected, ...
        'Meta', meta);
end
