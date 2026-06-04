function results = reg_4d_tcm_sweep()
%REG_4D_TCM_SWEEP Check 4D-8PSK-TCM efficiencies and impairment scenarios.

    reg_setup(1);

    effList = [2, 2.25, 2.5, 2.75];
    byteList = [1115, 1112, 1116, 1118];
    scenarios = {
        struct('Name',"ideal", 'SNR',100, 'CFO',0,      'Phase',0,  'Delay',0)
        struct('Name',"damaged_delay", 'SNR',20, 'CFO',20000,  'Phase',15, 'Delay',0.3)
        struct('Name',"stress", 'SNR',15, 'CFO',200000, 'Phase',10, 'Delay',0.4)
    };

    results = table(strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), false(0,1), ...
        'VariableNames', {'Scenario','Eff','BER','LockRate_pct','EVM_post_pct', ...
        'BestSampleOffset','NumBytes','Status','Pass'});

    fprintf('\n================ REG 4D-TCM SWEEP ================\n');

    for iEff = 1:numel(effList)
        for iSc = 1:numel(scenarios)
            sc = scenarios{iSc};
            p = struct('modType','4D-8PSK-TCM','symbolRate',1e6,'sps',8, ...
                'snr',sc.SNR,'cfo',sc.CFO,'phaseOffset',sc.Phase,'delay',sc.Delay, ...
                'channelCoding','none', ...
                'ModulationEfficiency',effList(iEff), ...
                'NumBytesInTransferFrame',byteList(iEff), ...
                'RolloffFactor',0.35, ...
                'hasASM',true, ...
                'hasRandomizer',false, ...
                'showFigures',false, ...
                'berWarmUpFrames',3, ...
                'berFrames',6, ...
                'tcmSearchAll',false, ...
                'tcmSampleOffsetSearchAll',true);

            fprintf('\n[4D] scenario=%s eff=%.2f\n', sc.Name, effList(iEff));
            out = reg_decode_output(run_ccsds_tm_evaluation(p));

            bestOff = NaN;
            if isfield(out,'BestTCMSampleOffset')
                bestOff = double(out.BestTCMSampleOffset);
            end

            pass = out.BER <= 5e-3 && out.LockRate >= 0.95;
            status = "PASS";
            if ~pass
                status = "FAIL";
            end

            results = [results; {string(sc.Name), effList(iEff), out.BER, ...
                out.LockRate*100, out.EVM_post_pct, bestOff, byteList(iEff), ...
                status, pass}]; %#ok<AGROW>
        end
    end

    disp(results);
    assert(all(results.Pass), '4D-TCM regression failed.');
end
