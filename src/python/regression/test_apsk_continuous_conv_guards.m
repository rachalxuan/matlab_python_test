function test_apsk_continuous_conv_guards()
% Invalid stream profiles must fail before TX, not fall back silently.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
base=struct('channelCoding','convolutional','ConvolutionalCodeRate','5/6', ...
    'ConvolutionalReceiveMode','stream-raw-asm','NumBytesInTransferFrame',258, ...
    'symbolRate',10e6,'sps',8,'PulseShapingFilter','root raised cosine', ...
    'DataPathMode','single','PCMFormat','NRZ-L','hasASM',true, ...
    'RandomizerEnabled',false,'noiseMode','off','showFigures',false);
bad={struct('RandomizerEnabled',true),struct('PCMFormat','NRZ-M'), ...
    struct('hasASM',false),struct('DataPathMode','dualIQ'), ...
    struct('channelCoding','concatenated','RSMessageLength',223, ...
        'RSInterleavingDepth',6,'IsRSMessageShortened',false), ...
    struct('channelCoding','concatenated','RSMessageLength',223, ...
        'RSInterleavingDepth',1,'IsRSMessageShortened',true,'RSShortenedMessageLength',200)};
count=0;
for modType={'16APSK','32APSK'}
    for k=1:numel(bad)
        p=base; p.modType=modType{1}; fields=fieldnames(bad{k});
        for j=1:numel(fields), p.(fields{j})=bad{k}.(fields{j}); end
        evalc('r=run_ccsds_tm_evaluation(p);');
        assert(~r.success && contains(r.errorIdentifier,'ContinuousConvUnsupportedProfile'), ...
            'Unexpected validation result for %s case %d: %s',p.modType,k,r.errorIdentifier);
        count=count+1;
    end
    % The old route must retain its unaligned-frame guard. Do not globally
    % remove the TX restriction simply because the stream route supports it.
    p=base; p.modType=modType{1}; p.ConvolutionalReceiveMode='legacy-coded-asm';
    evalc('r=run_ccsds_tm_evaluation(p);');
    assert(~r.success && contains(r.errorIdentifier,'HighRateConvFrameLengthUnsupported'));
    count=count+1;
end
fprintf('PASS: %d unsupported/legacy guard requests rejected.\n',count);
end
