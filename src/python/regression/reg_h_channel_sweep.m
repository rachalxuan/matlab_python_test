function results = reg_h_channel_sweep()
%REG_H_CHANNEL_SWEEP Check SISO multipath damage and optional known-H equalizer.

    reg_setup(3);

    base = struct('modType','PCM/PM/biphase-L','symbolRate',1e6,'sps',8, ...
        'snr',12,'cfo',200000,'phaseOffset',10,'delay',0.2, ...
        'channelCoding','none', ...
        'NumBytesInTransferFrame',1115, ...
        'ModulationIndex',pi/3, ...
        'hasASM',true, ...
        'hasRandomizer',false, ...
        'showFigures',false, ...
        'berWarmUpFrames',3, ...
        'berFrames',8);

    cases = {
        struct('Name',"baseline no H", 'EnableH',false, 'H',[], ...
            'EnableEq',false, 'MaxBER',2e-3, 'MinLock',0.95)
        struct('Name',"mild H", 'EnableH',true, ...
            'H',[1, 0, 0.25*exp(1j*pi/3), 0, 0.10*exp(-1j*pi/4)], ...
            'EnableEq',false, 'MaxBER',5e-3, 'MinLock',0.90)
        struct('Name',"strong H", 'EnableH',true, ...
            'H',[1, 0, 0.85*exp(1j*pi/3), 0, 0.60*exp(-1j*pi/4), 0, 0.40*exp(1j*pi/2)], ...
            'EnableEq',false, 'MaxBER',8e-2, 'MinLock',0.50)
        struct('Name',"strong H + MMSE EQ", 'EnableH',true, ...
            'H',[1, 0, 0.85*exp(1j*pi/3), 0, 0.60*exp(-1j*pi/4), 0, 0.40*exp(1j*pi/2)], ...
            'EnableEq',true, 'MaxBER',8e-2, 'MinLock',0.50)
    };

    results = table(strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), strings(0,1), false(0,1), ...
        'VariableNames', {'Case','BER','LockRate_pct','HNumTaps','HPowerGain_dB', ...
        'Status','Pass'});

    fprintf('\n================ REG H CHANNEL SWEEP ================\n');

    for k = 1:numel(cases)
        c = cases{k};
        p = base;
        p.enableHChannel = c.EnableH;
        if c.EnableH
            p.HMode = 'siso_multipath';
            p.H = c.H;
            p.normalizeHChannel = true;
        end
        p.enableEqualizer = c.EnableEq;
        if c.EnableEq
            p.equalizerMode = 'mmse';
            p.normalizeEqualizerOutput = true;
        end

        fprintf('\n[H] case=%s\n', c.Name);
        out = reg_decode_output(run_ccsds_tm_evaluation(p));

        hTaps = 0;
        hGain = NaN;
        if isfield(out,'HNumTaps')
            hTaps = out.HNumTaps;
            hGain = out.HPowerGain_dB;
        end

        pass = out.BER <= c.MaxBER && out.LockRate >= c.MinLock;
        status = "PASS";
        if ~pass
            status = "FAIL";
        end

        results = [results; {c.Name, out.BER, out.LockRate*100, hTaps, ...
            hGain, status, pass}]; %#ok<AGROW>
    end

    disp(results);
    assert(all(results.Pass), 'H-channel regression failed.');
end
