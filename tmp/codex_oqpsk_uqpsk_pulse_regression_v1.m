% Combined-TM pulse regression. Run the actual evaluator and preserve every
% failed case. TX truth is used only by tests, never for synchronization.
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'src','python'));
if ~exist('OQUPulseOptions','var'), OQUPulseOptions=struct(); end
if ~isfield(OQUPulseOptions,'ModTypes'), OQUPulseOptions.ModTypes=["OQPSK","UQPSK"]; end
if ~isfield(OQUPulseOptions,'Shapes'), OQUPulseOptions.Shapes=["root raised cosine","raised cosine","none"]; end
if ~isfield(OQUPulseOptions,'Codings'), OQUPulseOptions.Codings="none"; end
if ~isfield(OQUPulseOptions,'BERFrames'), OQUPulseOptions.BERFrames=120; end
% Include both aligned and non-aligned UQPSK 3-bit mapping groups. The RC
% acquisition limitation at 256 bytes must remain visible, not filtered out.
if ~isfield(OQUPulseOptions,'NumBytesInTransferFrame'), OQUPulseOptions.NumBytesInTransferFrame=[254 256]; end
if ~isfield(OQUPulseOptions,'ResultName'), OQUPulseOptions.ResultName='oq_uq_pulse_results'; end
outDir=fullfile(fileparts(mfilename('fullpath')),OQUPulseOptions.ResultName);
if ~exist(outDir,'dir'), mkdir(outDir); end
OQUPulseRows=struct([]); OQUPulseLogs={}; OQUPulseMetrics={};
for tfBytes=OQUPulseOptions.NumBytesInTransferFrame(:).'
for coding=string(OQUPulseOptions.Codings(:).')
for modType=string(OQUPulseOptions.ModTypes(:).')
for shape=string(OQUPulseOptions.Shapes(:).')
    p=struct('modType',char(modType),'symbolRate',10e6,'sps',8, ...
        'channelCoding',char(coding),'ConvolutionalCodeRate','1/2', ...
        'NumBytesInTransferFrame',tfBytes, ...
        'hasASM',true,'RandomizerEnabled',false, ...
        'DataPathMode','single','PCMFormat','NRZ-L','PulseShapingFilter',char(shape), ...
        'RolloffFactor',0.35,'FilterSpanInSymbols',10,'noiseMode','off', ...
        'cfo',0,'phaseOffset',0,'delay',0,'berWarmUpFrames',8, ...
        'berFrames',OQUPulseOptions.BERFrames,'excludeBERWarmUpFrames',true, ...
        'enableHChannel',false,'enableEqualizer',false,'showFigures',false, ...
        'enableReceiverTimeline',true);
    rng(917,'twister');
    logText=evalc('m=run_ccsds_tm_evaluation(p);');
    row=struct('Modulation',modType,'Shape',shape,'Coding',coding,'TFBytes',tfBytes, ...
        'BER',NaN,'FER',NaN,'ComparedFrames',0,'Coverage',"unavailable", ...
        'SampleRateConsistent',false,'Pass',false,'Error',"");
    if m.success
        row.BER=m.BER; row.FER=m.FER; row.ComparedFrames=m.CountedFrames;
        row.Coverage=string(m.MeasurementCoverage.Status);
        row.SampleRateConsistent=abs(m.ActualWaveformDuration_s*80e6 - ...
            (m.BurstCompletion.OriginalWaveformSamples+m.BurstCompletion.AppendedSamples))<1e-6;
        row.Pass=m.BER==0 && m.FER==0 && ...
            m.CountedFrames==p.berFrames && m.MeasurementCoverage.Complete && ...
            m.MeasurementCoverage.UnrecoveredFrames==0 && row.SampleRateConsistent && ...
            strcmp(m.PulseShapingFilter,shape) && m.BurstCompletion.Applied;
    else
        row.Error=string(m.errorMsg);
    end
    if isempty(OQUPulseRows), OQUPulseRows=row; else, OQUPulseRows(end+1)=row; end
    OQUPulseLogs{end+1}=logText;
    OQUPulseMetrics{end+1}=m;
    fprintf('%s | %s | %s | TF=%d: BER=%g FER=%g coverage=%s frames=%d pass=%d %s\n', ...
        modType,coding,shape,tfBytes,row.BER,row.FER,row.Coverage,row.ComparedFrames,row.Pass,row.Error);
    save(fullfile(outDir,'latest.mat'),'OQUPulseRows','OQUPulseLogs','OQUPulseMetrics','OQUPulseOptions');
end
end
end
end
OQUPulseResults=struct2table(OQUPulseRows);
writetable(OQUPulseResults,fullfile(outDir,'latest.csv'));
disp(OQUPulseResults);

% PSD and TX state continuity from the SAME production generator/adapter.
% Same input bits across shapes; guards and filter edges excluded from PSD.
fig=figure('Visible','off','Position',[100 100 1200 480]);
psdData=struct([]);
for im=1:numel(OQUPulseOptions.ModTypes)
    modType=string(OQUPulseOptions.ModTypes(im));
    ax=subplot(1,numel(OQUPulseOptions.ModTypes),im,'Parent',fig); hold(ax,'on');
    for shape=string(OQUPulseOptions.Shapes(:).')
        rng(917,'twister');
        pulseArgs={};
        if shape~="none", pulseArgs={'RolloffFactor',0.35,'FilterSpanInSymbols',10}; end
        g=ccsdsTMWaveformGenerator('Modulation',char(modType),'ChannelCoding','none', ...
            'NumBytesInTransferFrame',254,'SamplesPerSymbol',8, ...
            'PulseShapingFilter',char(shape),pulseArgs{:});
        input=int8(randi([0 1],double(g.NumInputBits)*32,1));
        [raw,encoded]=g(input);
        [x,completion]=HelperTMCompleteBurst(g,raw,encoded,input,80e6,struct());
        assert(completion.OriginalModulatedBits==numel(encoded),'Unexpected buffered TX bits in aligned test');
        generatorInfo=info(g);
        assert(completion.OriginalWaveformSamples==numel(encoded)/double(generatorInfo.NumBitsPerSymbol)*8);
        assert(completion.AppendedSamples==completion.AppendedEncodedBits/double(generatorInfo.NumBitsPerSymbol)*8);
        if modType=="OQPSK" && shape=="none"
            % Real transitions stay on symbol epochs; Q transitions are T/2 later.
            transitionsI=find(abs(diff(real(raw)))>1e-10)+1;
            transitionsQ=find(abs(diff(imag(raw)))>1e-10)+1;
            assert(all(mod(transitionsI-1,8)==0));
            assert(all(mod(transitionsQ-1,8)==4));
        end
        % Chunk boundaries must not reset mapper/filter/half-symbol state.
        g2=clone(g); reset(g2); split=double(g2.NumInputBits)*13;
        [xa,~]=g2(input(1:split)); [xb,~]=g2(input(split+1:end));
        assert(isequal(raw,[xa;xb]),'TX changed at a generator call boundary');
        x=x(129*8:completion.OriginalWaveformSamples-128*8);
        x=x/sqrt(mean(abs(x).^2));
        [spectrum,f]=pwelch(x,hann(4096),2048,8192,80e6,'centered');
        plot(ax,f/1e6,10*log10(max(spectrum,realmin)),'DisplayName',char(shape));
        psdRow=struct('Modulation',modType,'Shape',shape,'Hz',f,'PSD',spectrum);
        if isempty(psdData), psdData=psdRow; else, psdData(end+1)=psdRow; end
    end
    title(ax,char(modType)); xlabel(ax,'Frequency (MHz)'); ylabel(ax,'PSD (dB/Hz, unit mean power)');
    grid(ax,'on'); legend(ax,'show','Location','southwest'); ylim(ax,[-140 -60]);
end
exportgraphics(fig,fullfile(outDir,'pulse_psd_comparison.png'),'Resolution',160); close(fig);
save(fullfile(outDir,'pulse_psd_comparison.mat'),'psdData');
assert(all(OQUPulseResults.Pass),'At least one pulse case failed; inspect latest.mat logs.');
fprintf('PASS: all requested pulses, complete coverage, TX continuity and rate checks.\n');
