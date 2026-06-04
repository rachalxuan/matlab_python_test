function results = reg_pcm_phase_sweep()
%REG_PCM_PHASE_SWEEP Check PCM/PSK/PM and PCM/PM/biphase-L demodulator paths.

    reg_setup(2);

    mods = {
        struct('Name',"PCM/PSK/PM", 'Extra', struct( ...
            'PCMFormat','NRZ-L', ...
            'SubcarrierWaveform','sine', ...
            'SubcarrierToSymbolRateRatio',2))
        struct('Name',"PCM/PM/biphase-L", 'Extra', struct())
    };

    scenarios = {
        struct('Name',"ideal", 'SNR',100, 'CFO',0,      'Phase',0,  'Delay',0,   'MaxBER',0,      'MinLock',1)
        struct('Name',"delay", 'SNR',100, 'CFO',0,      'Phase',0,  'Delay',0.2, 'MaxBER',1e-4,   'MinLock',1)
        struct('Name',"cfo_damaged", 'SNR',20, 'CFO',20000, 'Phase',10, 'Delay',0.2, 'MaxBER',2e-3, 'MinLock',0.90)
        struct('Name',"low_snr", 'SNR',8, 'CFO',20000, 'Phase',10, 'Delay',0.2, 'MaxBER',2e-2, 'MinLock',0.70)
    };

    results = table(strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), false(0,1), ...
        'VariableNames', {'Modulation','Scenario','SNR','CFO','Delay','BER', ...
        'LockRate_pct','Status','Pass'});

    fprintf('\n================ REG PCM PHASE SWEEP ================\n');

    for iMod = 1:numel(mods)
        for iSc = 1:numel(scenarios)
            m = mods{iMod};
            sc = scenarios{iSc};
            p = struct('modType',char(m.Name),'symbolRate',1e6,'sps',8, ...
                'snr',sc.SNR,'cfo',sc.CFO,'phaseOffset',sc.Phase,'delay',sc.Delay, ...
                'channelCoding','none', ...
                'NumBytesInTransferFrame',1115, ...
                'ModulationIndex',pi/3, ...
                'hasASM',true, ...
                'hasRandomizer',false, ...
                'showFigures',false, ...
                'berWarmUpFrames',3, ...
                'berFrames',8);

            p = apply_extra_fields(p, m.Extra);

            fprintf('\n[PCM] modulation=%s scenario=%s\n', m.Name, sc.Name);
            out = reg_decode_output(run_ccsds_tm_evaluation(p));

            pass = out.BER <= sc.MaxBER && out.LockRate >= sc.MinLock;
            status = "PASS";
            if ~pass
                status = "FAIL";
            end

            results = [results; {m.Name, sc.Name, sc.SNR, sc.CFO, sc.Delay, ...
                out.BER, out.LockRate*100, status, pass}]; %#ok<AGROW>
        end
    end

    disp(results);
    assert(all(results.Pass), 'PCM phase regression failed.');
end

function p = apply_extra_fields(p, extra)
    names = fieldnames(extra);
    for k = 1:numel(names)
        p.(names{k}) = extra.(names{k});
    end
end
