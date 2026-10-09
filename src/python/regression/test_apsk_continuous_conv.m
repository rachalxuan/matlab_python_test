function outputDir=test_apsk_continuous_conv(suite,rateFilter)
% Real ordinary-TM TX / pilotless APSK / unchanged continuous conv receiver.
% Staged suites: conv -> rs -> rs-spots -> phase. No truth-fed acquisition.
if nargin<1, suite='conv'; end
if nargin<2, rateFilter=["1/2","3/4","5/6","7/8","2/3"]; end
assert(any(strcmp(suite,{'conv','rs','rs-spots','phase'})));
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
outputDir=tempname(fullfile(root,'tmp')); mkdir(outputDir);
diary(fullfile(outputDir,'console.txt')); cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('APSK continuous conv %s: %s\n',suite,outputDir);
checkSoftLabels();
p=struct('symbolRate',10e6,'sps',8,'NumBytesInTransferFrame',258, ...
    'channelCoding','convolutional','ConvolutionalReceiveMode','stream-raw-asm', ...
    'hasASM',true,'PCMFormat','NRZ-L','RandomizerEnabled',false,'DataPathMode','single', ...
    'noiseMode','off','cfo',0,'phaseOffset',0,'delay',0, ...
    'berWarmUpFrames',8,'berFrames',120,'excludeBERWarmUpFrames',true, ...
    'enableHChannel',false,'enableEqualizer',false,'enableReceiverTimeline',true, ...
    'captureBaselineData',true,'showFigures',false,'randomSeed',20260927, ...
    'debugContinuousConvReceiver',true);
cases={};
for rate=string(rateFilter)
    for modType=["16APSK","32APSK"]
        for pulse=["root raised cosine","none"]
            q=p; q.modType=char(modType); q.PulseShapingFilter=char(pulse);
            q.ConvolutionalCodeRate=char(rate);
            switch suite
                case 'conv'
                    cases{end+1}=q; %#ok<AGROW>
                case 'rs'
                    q.channelCoding='concatenated'; q.RSMessageLength=223;
                    q.RSInterleavingDepth=1; q.IsRSMessageShortened=false;
                    q.NumBytesInTransferFrame=223; cases{end+1}=q; %#ok<AGROW>
                case 'rs-spots'
                    depths=[1 2 3 4 5 8]; rates=["1/2","3/4","5/6","7/8","2/3","7/8"];
                    for j=find(rates==rate)
                        t=q; t.channelCoding='concatenated'; t.RSMessageLength=239;
                        t.RSInterleavingDepth=depths(j); t.IsRSMessageShortened=false;
                        t.NumBytesInTransferFrame=239*depths(j); cases{end+1}=t; %#ok<AGROW>
                    end
                case 'phase'
                    % Only 3/4: exercise ambiguity, alternate seed and mapping remainder.
                    if rate~="3/4", continue; end
                    for phase=[90 -90]
                        t=q; t.phaseOffset=phase; t.randomSeed=917;
                        t.NumBytesInTransferFrame=255; cases{end+1}=t; %#ok<AGROW>
                    end
            end
        end
    end
end
assert(~isempty(cases)); rows={};
for k=1:numel(cases)
    p=cases{k}; puncture=ccsdsTMConvolutionalPunctureConfig(p.ConvolutionalCodeRate);
    rawBits=32+8*p.NumBytesInTransferFrame;
    if strcmp(p.channelCoding,'concatenated'), rawBits=32+8*255*p.RSInterleavingDepth; end
    remainder=mod(rawBits,puncture.InputBitsPerPeriod);
    fprintf('\nRUN %d/%d %s %s %s rate=%s TF=%d raw=%d remainder=%d/%d phase=%g\n', ...
        k,numel(cases),p.modType,p.PulseShapingFilter,p.channelCoding, ...
        p.ConvolutionalCodeRate,p.NumBytesInTransferFrame,rawBits,remainder, ...
        puncture.InputBitsPerPeriod,p.phaseOffset);
    rng(p.randomSeed,'twister'); logText=evalc('r=run_ccsds_tm_evaluation(p);');
    row=struct('ModType',string(p.modType),'Pulse',string(p.PulseShapingFilter), ...
        'Coding',string(p.channelCoding),'Rate',string(p.ConvolutionalCodeRate), ...
        'TFBytes',p.NumBytesInTransferFrame,'RawBits',rawBits,'PunctureRemainder',remainder, ...
        'BER',NaN,'FER',NaN,'ComparedFrames',0,'CoverageComplete',false, ...
        'RSRawErrors',NaN,'RSCorrections',NaN,'RSMappedFrames',NaN, ...
        'SelectedOffset',NaN,'ASMRun',NaN,'BufferedMapperBits',NaN,'Pass',false,'Error',"");
    try
        assert(r.success,'%s',r.errorMsg);
        row.BER=r.BER; row.FER=r.FER; row.ComparedFrames=r.CountedFrames;
        cov=r.MeasurementCoverage; row.CoverageComplete=cov.Complete;
        row.SelectedOffset=r.ContinuousConvSelectedOffset; row.ASMRun=r.ContinuousConvLongestGoodASMRun;
        row.BufferedMapperBits=r.BurstCompletion.BufferedModulationBits;
        assert(strcmp(r.ConvolutionalReceiveMode,'stream-raw-asm'));
        assert(r.ContinuousConvReceiverAvailable && row.ASMRun>=4);
        assert(r.BER==0 && r.FER==0 && r.CountedFrames==120 && cov.Complete && ...
            cov.ExpectedFrames==120 && cov.ComparedFrames==120 && ...
            cov.UnrecoveredFrames==0 && cov.RecoveredNotComparedFrames==0);
        assert(strcmp(r.WaveformMode,'ordinaryTM') && strcmp(r.APSKReceiverMode,'pilotless') && ...
            ~r.HasTMAPSKPilots && r.PilotlessAPSKApplied);
        assert(r.Fs==p.symbolRate*p.sps && r.BurstCompletion.Applied);
        if strcmp(p.PulseShapingFilter,'none')
            b=r.BurstCompletion; tx=r.BaselineCapture.TxWaveform;
            assert(b.RectangularSymbolHoldApplied && b.OriginalWaveformSamples== ...
                b.GeneratorOutputSamplesBeforeHold*p.sps);
            assert(numel(tx)==b.OriginalWaveformSamples+b.AppendedSamples);
            for segment={tx(1:b.OriginalWaveformSamples),tx(b.OriginalWaveformSamples+1:end)}
                g=reshape(segment{1},p.sps,[]); assert(~isempty(g) && all(all(g==g(1,:))));
            end
        end
        if strcmp(p.channelCoding,'concatenated')
            row.RSRawErrors=r.ContinuousConvOuterRSMeasurementRawCodewordBitErrors;
            row.RSCorrections=r.ContinuousConvOuterRSMeasurementCorrectedSymbols;
            row.RSMappedFrames=r.ContinuousConvOuterRSMeasurementMappedFrames;
            assert(r.ContinuousConvOuterRSDecodeApplied && row.RSRawErrors==0 && ...
                row.RSCorrections==0 && row.RSMappedFrames==120 && ...
                r.ContinuousConvOuterRSMeasurementRawCodewordErrorFrames==0 && ...
                r.ContinuousConvOuterRSMeasurementUncorrectableFrames==0);
        end
        row.Pass=true;
    catch ex
        row.Error=string(getReport(ex,'extended','hyperlinks','off'));
    end
    % Successful files retain all metrics/logs; failures also retain samples.
    if row.Pass, r=rmfield(r,'BaselineCapture'); end
    save(fullfile(outputDir,sprintf('case_%02d.mat',k)),'p','r','logText','row','-v7');
    rows{end+1}=row; Summary=struct2table(vertcat(rows{:})); %#ok<AGROW>
    writetable(Summary,fullfile(outputDir,'summary.csv'));
    save(fullfile(outputDir,'summary.mat'),'Summary');
    fprintf('RESULT BER=%g FER=%g compared=%d/120 complete=%d rawRSerr=%g RScorrected=%g offset=%g ASMrun=%g PASS=%d\n', ...
        row.BER,row.FER,row.ComparedFrames,row.CoverageComplete,row.RSRawErrors, ...
        row.RSCorrections,row.SelectedOffset,row.ASMRun,row.Pass);
    % Stop the staged progression at the first failure; never sweep past it.
    assert(row.Pass,'APSKConv:Failure','%s\nCapture: %s',row.Error,outputDir);
end
fprintf('PASS %s: %d/%d cases.\n',suite,height(Summary),numel(cases));
end

function checkSoftLabels()
for format=[14 21]
    ref=HelperCCSDSFACMReferenceConstellation(format); m=log2(numel(ref));
    bits=int2bit(0:numel(ref)-1,m); bits=bits(:);
    soft=HelperCCSDSFACMDemodulate(ref,format,0.1);
    assert(isequal(soft>0,logical(bits)),'APSK positive-soft-means-1 / MSB order mismatch.');
    demod=HelperCCSDSTMDemodulator('Modulation',sprintf('%dAPSK',numel(ref)), ...
        'ChannelCoding','convolutional','NoiseVariance',0.1);
    actual=demod(ref);
    assert(isequal(actual>0,logical(bits)),'Production APSK demapper polarity/order mismatch.');
    release(demod);
    fprintf('SOFT CHECK %dAPSK: all %d labels, MSB order and positive=1 verified.\n',numel(ref),numel(ref));
end
end
