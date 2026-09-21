function test_web_parameter_contract
% Short, genuine no-H receive tests, not a long-run BER qualification.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
folder=fullfile(root,'artifacts','ccsds','frontend-contract');
if ~isfolder(folder), mkdir(folder); end
base=struct('modType','QPSK','channelCoding','none','WaveformMode','ordinaryTM', ...
    'symbolRate',50e6,'sps',8,'snr',100,'noiseMode','off', ...
    'cfo',0,'phaseOffset',0,'delay',0,'NumBytesInTransferFrame',1151, ...
    'hasASM',true,'RandomizerEnabled',false,'AGCEnabled',false, ...
    'DataPathMode','single','enableHChannel',false,'enableEqualizer',false, ...
    'equalizerMode','off','adaptiveEqualizerSamplingMode','off', ...
    'berWarmUpFrames',8,'berFrames',12,'excludeBERWarmUpFrames',true, ...
    'enableReceiverTimeline',true,'showFigures',false,'outputDir',folder, ...
    'RolloffFactor',0.35,'FilterSpanInSymbols',10);
cases={
    'MSK conv5/6', struct('modType','MSK','channelCoding','convolutional','ConvolutionalCodeRate','5/6');
    '16APSK TM', struct('modType','16APSK','channelCoding','convolutional','ConvolutionalCodeRate','5/6','APSKReceiverMode','pilotless','HasTMAPSKPilots',false);
    '32APSK TM', struct('modType','32APSK','channelCoding','convolutional','ConvolutionalCodeRate','5/6','APSKReceiverMode','pilotless','HasTMAPSKPilots',false);
    '32QAM RS+conv1/2', struct('modType','32QAM','channelCoding','concatenated','ConvolutionalCodeRate','1/2','RSMessageLength',223,'RSInterleavingDepth',5,'IsRSMessageShortened',false);
    'QPSK Turbo3568', struct('channelCoding','Turbo','CodeRate','1/2','NumBitsInInformationBlock',3568);
    'QPSK LDPC1024', struct('channelCoding','LDPC','CodeRate','1/2','NumBitsInInformationBlock',1024,'IsLDPCOnSMTF',false);
    'QPSK RRC span12', struct('FilterSpanInSymbols',12);
    'QPSK concat7/8 I1', struct('channelCoding','concatenated','ConvolutionalCodeRate','7/8','RSMessageLength',223,'RSInterleavingDepth',1,'IsRSMessageShortened',false)
};
rows=struct([]);
for k=1:size(cases,1)
    p=base; fields=fieldnames(cases{k,2});
    for j=1:numel(fields), p.(fields{j})=cases{k,2}.(fields{j}); end
    rng(8401,'twister');
    fprintf('\n[Web contract %d/%d] %s\n',k,size(cases,1),cases{k,1});
    [log,r]=evalc('run_ccsds_tm_evaluation(p)');
    fid=fopen(fullfile(folder,sprintf('case-%02d.log',k)),'w'); fprintf(fid,'%s',log); fclose(fid);
    rows(k).Case=cases{k,1}; rows(k).Success=r.success;
    rows(k).BER=NaN; rows(k).ComparedFrames=0; rows(k).CoverageComplete=false; rows(k).Error='';
    if r.success
        rows(k).BER=r.BER;
        if isfield(r,'ReceiverTimeline') && r.ReceiverTimeline.Available
            c=r.ReceiverTimeline.MeasurementCoverage;
            rows(k).ComparedFrames=c.ComparedFrames;
            rows(k).CoverageComplete=c.Complete;
        end
    else
        rows(k).Error=r.error;
    end
    disp(rows(k));
end
fid=fopen(fullfile(folder,'summary.json'),'w'); fprintf(fid,'%s',jsonencode(rows)); fclose(fid);
disp(struct2table(rows));
assert(all([rows.Success]),'A web parameter profile failed; inspect case logs.');
assert(all([rows.BER]==0),'A no-H profile has errors; do not label it as passed.');
assert(all([rows.ComparedFrames]>0),'Zero compared bits is not a successful test.');
if ~all([rows.CoverageComplete])
    warning('Web regression includes incomplete measurement coverage; see summary. BER=0 applies only to compared bits.');
end

% The former error used an inactive 223-byte property (1816 bits). Check the
% actual RS encoder output length without running an entire invalid job.
g=ccsdsTMWaveformGenerator('Modulation','32QAM','ChannelCoding','concatenated', ...
    'ConvolutionalCodeRate','5/6','RSMessageLength',223,'RSInterleavingDepth',5);
rejected=false;
try
    g(zeros(g.NumInputBits,1,'int8'));
catch err
    rejected=contains(err.message,'10232 bits') && contains(err.message,'ASM+RS');
end
assert(rejected,'Invalid concat5/6 must report the real RS-coded frame length.');
fprintf('PASS: short web parameter regressions and coded-length rejection.\n');
end
