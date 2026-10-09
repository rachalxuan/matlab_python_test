function report = run_deployment_tests(varargin)
%RUN_DEPLOYMENT_TESTS Portable, short tests of the actual deployed backend.
% Run in a fresh MATLAB session. No frontend, Python or original repo needed.
% run_deployment_tests('Profile','quick')
% run_deployment_tests('Profile','extended','CaseIds',{'qpsk_ldpc'})
% run_deployment_tests('Profile','channel','ChannelFile','D:/.../ChannelData.mat')
% Use 'DryRun',true to list cases without starting computation.

ip=inputParser;
addParameter(ip,'BackendRoot',fileparts(fileparts(mfilename('fullpath'))));
addParameter(ip,'Profile','quick');
addParameter(ip,'CaseIds',{});
addParameter(ip,'ChannelFile','');
addParameter(ip,'ChannelSampleRateHz',100000);
addParameter(ip,'OutputDir','');
addParameter(ip,'DryRun',false);
addParameter(ip,'FailOnFailure',true);
parse(ip,varargin{:}); opt=ip.Results;
root=char(opt.BackendRoot);
assert(isfile(fullfile(root,'run_ccsds_tm_evaluation.m')), ...
    'BackendRoot must contain run_ccsds_tm_evaluation.m.');
cases=localCases(lower(string(opt.Profile)),char(opt.ChannelFile),opt.ChannelSampleRateHz);
for k=1:numel(cases), cases(k).Seed=8401+k; end
if ~isempty(opt.CaseIds)
    wanted=string(opt.CaseIds);
    assert(all(ismember(wanted,string({cases.Id}))), ...
        'Unknown CaseIds; use DryRun to list the selected profile.');
    cases=cases(ismember(string({cases.Id}),wanted));
end
if opt.DryRun
    report=struct('Profile',char(opt.Profile),'Cases',cases);
    disp(string({cases.Id})'); return;
end

oldPath=path; oldDir=pwd; oldRng=rng;
cleanup=onCleanup(@()localRestore(oldPath,oldDir,oldRng)); %#ok<NASGU>
restoredefaultpath;
cd(root); addpath(root,'-begin');
addpath(fullfile(root,'apsk_pilotless_stage2_asm'),'-end');
rehash;
paths=localCheckPaths(root);
output=char(opt.OutputDir);
if isempty(output)
    output=fullfile(root,'artifacts','acceptance', ...
        [char(opt.Profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
end
assert(~isfolder(output),'OutputDir already exists; use a new directory to keep previous evidence.');
mkdir(output);
rows=repmat(struct('Id','','Seed',0,'Pass',false,'Status','NOT_RUN','Acceptance','', ...
    'BER',NaN,'ComparedBits',0,'ComparedFrames',0,'ExpectedFrames',0, ...
    'CoverageComplete',false,'ElapsedSeconds',NaN,'Error',''),numel(cases),1);
report=struct('SchemaVersion',1,'Profile',char(opt.Profile), ...
    'BackendRoot',root,'OutputDir',output,'MATLABRelease',version('-release'), ...
    'MATLABVersion',version,'Computer',computer,'Toolboxes',ver, ...
    'ResolvedPaths',paths,'CreatedAt',char(datetime('now')), ...
    'Purpose','Short deployment checks; not BER performance qualification.', ...
    'Rows',rows,'AllPassed',false);
for k=1:numel(cases)
    c=cases(k); p=c.Params; row=rows(k);
    row.Id=c.Id; row.Seed=c.Seed; row.Acceptance=c.Acceptance;
    caseDir=fullfile(output,c.Id); mkdir(caseDir);
    p.outputDir=caseDir;
    rng(c.Seed,'twister');
    fprintf('\n[%d/%d] %s\n',k,numel(cases),c.Id);
    t=tic;
    try
        [logText,r]=evalc('run_ccsds_tm_evaluation(p)');
        localText(fullfile(caseDir,'matlab.log'),logText);
        save(fullfile(caseDir,'result.mat'),'p','r');
        assert(isstruct(r) && isfield(r,'success') && r.success, ...
            'MATLAB failed: %s',localError(r));
        row.BER=double(r.BER);
        coverage=struct();
        if isfield(r,'MeasurementCoverage'), coverage=r.MeasurementCoverage;
        elseif isfield(r,'ReceiverTimeline') && isfield(r.ReceiverTimeline,'MeasurementCoverage')
            coverage=r.ReceiverTimeline.MeasurementCoverage;
        end
        if isfield(coverage,'ComparedBits'), row.ComparedBits=double(coverage.ComparedBits); end
        if isfield(coverage,'ComparedFrames'), row.ComparedFrames=double(coverage.ComparedFrames); end
        if isfield(coverage,'ExpectedFrames'), row.ExpectedFrames=double(coverage.ExpectedFrames); end
        if isfield(coverage,'Complete'), row.CoverageComplete=logical(coverage.Complete); end
        assert(isfield(r,'NoiseMode') && strcmpi(r.NoiseMode,'off'),'Noise mode was not off.');
        if strcmp(c.Acceptance,'noiseless-reception')
            assert(~r.HEnabled,'No-H baseline unexpectedly enabled a channel.');
            assert(isfinite(row.BER) && row.BER==0,'Noiseless case has invalid/nonzero BER.');
            assert(row.ComparedBits>0,'No compared bits: cannot pass.');
            assert(row.CoverageComplete,'Measurement coverage incomplete: cannot pass.');
            row.Status='PASS';
        else
            assert(r.HEnabled && strcmpi(r.HMode,'h_matrix_file'), ...
                'Requested MAT channel was not enabled.');
            assert(isfield(r,'channelMeta') && isstruct(r.channelMeta), ...
                'No loaded channel metadata in result.');
            row.Status='LOAD_OK';
            % This case verifies file loading only. BER/coverage are reported,
            % not silently judged against an arbitrary channel threshold.
        end
        row.Pass=true;
    catch err
        row.Status='FAIL'; row.Error=getReport(err,'extended','hyperlinks','off');
        localText(fullfile(caseDir,'failure.txt'),row.Error);
    end
    row.ElapsedSeconds=toc(t); rows(k)=row;
    report.Rows=rows; report.AllPassed=all([rows.Pass]);
    localText(fullfile(output,'summary.json'),jsonencode(report));
    save(fullfile(output,'summary.mat'),'report');
    fprintf('%s: %s | BER=%g | frames=%g/%g | %.1fs\n', ...
        row.Id,row.Status,row.BER,row.ComparedFrames,row.ExpectedFrames,row.ElapsedSeconds);
end
disp(struct2table(rows,'AsArray',true));
fprintf('Report: %s\n',fullfile(output,'summary.json'));
if opt.FailOnFailure
    assert(report.AllPassed,'Deployment tests failed. Read summary.json and per-case failure.txt.');
end
end

function cases=localCases(profile,channelFile,channelSampleRate)
p=struct('modType','QPSK','channelCoding','none','WaveformMode','ordinaryTM', ...
    'PCMFormat','NRZ-L','DataPathMode','single','symbolRate',30e6,'sps',8, ...
    'noiseMode','off','snr',100,'cfo',0,'phaseOffset',0,'delay',0, ...
    'NumBytesInTransferFrame',1151,'hasASM',true,'TMDataSource','random', ...
    'RandomizerEnabled',false,'RandomizerFECPosition','afterEncoding', ...
    'AGCEnabled',false,'enableHChannel',false,'HMode','none', ...
    'normalizeHChannel',false,'enableEqualizer',false,'equalizerMode','off', ...
    'adaptiveEqualizerSamplingMode','off','berWarmUpFrames',8,'berFrames',12, ...
    'excludeBERWarmUpFrames',true,'enableReceiverTimeline',true, ...
    'enableRuntimeLockTelemetry',true,'enableWebMonitor',false, ...
    'PulseShapingFilter','root raised cosine','RolloffFactor',0.35, ...
    'FilterSpanInSymbols',10,'remoteMode',false,'includeRawData',false,'showFigures',false);
cases=struct('Id',{},'Params',{},'Acceptance',{});
if profile=="channel"
    assert(isfile(channelFile),'Channel profile requires an existing ChannelFile.');
    p.enableHChannel=true; p.HMode='h_matrix_file'; p.channelFilePath=channelFile;
    p.channelSampleRateHz=channelSampleRate; p.channelInterpolationMethod='linear';
    p.channelOutOfRangeMode='wrap'; p.normalizeHChannel=true;
    cases=struct('Id','qpsk_mat_channel','Params',p,'Acceptance','channel-load'); return;
end
assert(any(profile==["quick","extended"]),'Profile must be quick, extended or channel.');
cases(end+1)=localCase('qpsk_none',p,struct());
cases(end+1)=localCase('qpsk_conv56',p,struct('channelCoding','convolutional', ...
    'ConvolutionalCodeRate','5/6','ConvolutionalReceiveMode','stream-raw-asm'));
cases(end+1)=localCase('qpsk_ldpc',p,struct('channelCoding','LDPC','CodeRate','1/2', ...
    'NumBitsInInformationBlock',1024,'IsLDPCOnSMTF',false,'LDPCCodeblockSize',1));
cases(end+1)=localCase('16apsk_conv56',p,struct('modType','16APSK', ...
    'channelCoding','convolutional','ConvolutionalCodeRate','5/6', ...
    'ConvolutionalReceiveMode','stream-raw-asm','APSKReceiverMode','pilotless','HasTMAPSKPilots',false));
if profile=="quick", return; end
cases(end+1)=localCase('qpsk_turbo',p,struct('channelCoding','Turbo', ...
    'CodeRate','1/2','NumBitsInInformationBlock',3568));
cases(end+1)=localCase('qpsk_tpc',p,struct('channelCoding','TPC', ...
    'TPCCodeRate','2/3','TPCBlocksPerTF',4,'TPCInterleaver','auto'));
cases(end+1)=localCase('8psk_rs',p,struct('modType','8PSK','channelCoding','RS', ...
    'RSMessageLength',223,'RSInterleavingDepth',1,'IsRSMessageShortened',false,'NumBytesInTransferFrame',223));
cases(end+1)=localCase('16qam_none',p,struct('modType','16QAM'));
cases(end+1)=localCase('32qam_concat',p,struct('modType','32QAM','channelCoding','concatenated', ...
    'ConvolutionalCodeRate','1/2','ConvolutionalReceiveMode','stream-raw-asm', ...
    'RSMessageLength',223,'RSInterleavingDepth',5,'IsRSMessageShortened',false,'NumBytesInTransferFrame',1115));
cases(end+1)=localCase('32apsk_conv56',p,struct('modType','32APSK', ...
    'channelCoding','convolutional','ConvolutionalCodeRate','5/6', ...
    'ConvolutionalReceiveMode','stream-raw-asm','APSKReceiverMode','pilotless','HasTMAPSKPilots',false));
cases(end+1)=localCase('oqpsk_none',p,struct('modType','OQPSK'));
cases(end+1)=localCase('uqpsk_none',p,struct('modType','UQPSK','RRatio',2,'ARatio',2, ...
    'enableUQPSKFFTCoarseCFO',true));
end

function c=localCase(id,p,updates)
names=fieldnames(updates);
for k=1:numel(names), p.(names{k})=updates.(names{k}); end
c=struct('Id',id,'Params',p,'Acceptance','noiseless-reception');
end

function resolved=localCheckPaths(root)
names={'run_ccsds_tm_evaluation','ccsdsTMWaveformGenerator','HelperCCSDSTMDecoder', ...
    'HelperTMAGC','HelperTMAPSKCarrierRecovery','TPC_encoder','TPC_decoder'};
resolved=struct();
for k=1:numel(names)
    name=names{k}; actual=which(name);
    if strcmp(name,'HelperTMAPSKCarrierRecovery')
        expected=fullfile(root,'apsk_pilotless_stage2_asm',[name '.m']);
    else
        expected=fullfile(root,[name '.m']);
    end
    assert(strcmpi(strrep(actual,'\','/'),strrep(expected,'\','/')), ...
        'Wrong function selected for %s: %s',name,actual);
    resolved.(name)=actual;
end
assert(isfile(fullfile(root,'FM_SOQPSK','FM_SOQPSK','data_training.mat')), ...
    'Missing FM training data.');
assert(isfile(fullfile(root,'err_p64.txt')), ...
    'Missing TPC data table err_p64.txt; this is not an error log.');
end

function msg=localError(r)
msg='No error detail returned';
if isstruct(r)
    if isfield(r,'error'), msg=char(string(r.error));
    elseif isfield(r,'errorMsg'), msg=char(string(r.errorMsg)); end
end
end

function localText(file,text)
fid=fopen(file,'w','n','UTF-8'); assert(fid~=-1,'Cannot open report file: %s',file);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',text);
end

function localRestore(oldPath,oldDir,oldRng)
path(oldPath); cd(oldDir); rng(oldRng);
end
