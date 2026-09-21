function HelperTMMonitorPublish(opt,stage,res,ctx)
% Read-only monitoring side channel. Never changes receiver state/results.
% Stages arrive during execution; audited counters arrive ONLY after the
% selected hypothesis has been evaluated. This is NOT a streaming receiver.
if ~isfield(opt,'enableWebMonitor') || ~opt.enableWebMonitor || ...
        ~isfield(opt,'outputDir') || isempty(opt.outputDir)
    return;
end
if nargin<3, res=struct(); end
if nargin<4, ctx=struct(); end
try
    snapshot=struct('schemaVersion',1,'processingMode','batch', ...
        'stage',char(stage),'publishedAtUnix',posixtime(datetime('now','TimeZone','UTC')), ...
        'metricsReady',false,'modType',char(string(opt.modType)), ...
        'channelCoding',char(string(opt.channelCoding)));
    if isfield(res,'ReceiverTimeline')
        timeline=res.ReceiverTimeline;
        % No TX payload, raw lock arrays or candidate hypotheses on the wire.
        names={'Available','Reason','Mode','TimeReference','TimeAlignment', ...
            'MetricDomain','Rows','Summary','MeasurementCoverage','ChannelCoding','DecoderMode'};
        snapshot.timeline=struct();
        for k=1:numel(names)
            if isfield(timeline,names{k})
                snapshot.timeline.(names{k})=timeline.(names{k});
            end
        end
        snapshot.metricsReady=logical(timeline.Available);
    end
    if isfield(res,'RuntimeLockTelemetry')
        snapshot.locks=struct();
        for name={'Carrier','Timing','Frame'}
            track=res.RuntimeLockTelemetry.(name{1});
            fields={'Available','Source','Reason','LockRate','LockedAtEnd', ...
                'LossEvents','Reacquisitions'};
            info=struct();
            for k=1:numel(fields)
                if isfield(track,fields{k}), info.(fields{k})=track.(fields{k}); end
            end
            if isfield(track,'Time_s') && numel(track.Time_s)>1
                info.ObservationPeriod_s=median(diff(track.Time_s));
            end
            snapshot.locks.(name{1})=info;
        end
    end
    if isfield(res,'AdaptiveEqualizerEnabled')
        applied=logical(res.AdaptiveEqualizerEnabled);
        if isfield(res,'AdaptiveFractionalEqualizerApplied')
            applied=applied || logical(res.AdaptiveFractionalEqualizerApplied);
        end
        snapshot.equalizer=struct('applied',applied, ...
            'meaning','applied is not a lock or correct-decoding guarantee');
    end
    if isfield(ctx,'fineSynced') && ~isempty(ctx.fineSynced)
        z=ctx.fineSynced(:);
        ix=unique(round(linspace(1,numel(z),min(numel(z),2048))));
        z=z(ix); z=z(isfinite(real(z)) & isfinite(imag(z)));
        snapshot.constellation=struct('source','ctx.fineSynced after selected global rotation', ...
            'timeResolved',false,'i',real(z),'q',imag(z), ...
            'meaning','whole-record receiver samples; not current-frame samples or hard decisions');
    end
    if isfield(ctx,'rxWaveform') && numel(ctx.rxWaveform)>1
        % Bounded, explicitly relative display. No invented absolute RF power.
        n=min(4096,numel(ctx.rxWaveform)); x=ctx.rxWaveform(1:n);
        w=0.5-0.5*cos(2*pi*(0:n-1)'/max(1,n-1));
        power=abs(fftshift(fft(x(:).*w))).^2;
        power=10*log10(max(power,realmin)/max(max(power),realmin));
        snapshot.spectrum=struct('source','first receiver waveform window', ...
            'timeResolved',false,'frequencyMHz',((-floor(n/2):ceil(n/2)-1)'/n)*ctx.Fs/1e6, ...
            'relativeDB',power,'sampleCount',n);
    end
    folder=char(opt.outputDir);
    if ~isfolder(folder), mkdir(folder); end
    pending=fullfile(folder,'receiver-monitor.pending');
    fid=fopen(pending,'w','n','UTF-8');
    if fid<0, error('ReceiverMonitor:Write','Cannot open monitor snapshot.'); end
    cleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'%s',jsonencode(snapshot));
    clear cleanup;
    movefile(pending,fullfile(folder,'receiver-monitor.json'),'f');
catch err
    % Observability must never turn successful reception into a failure.
    warning('ReceiverMonitor:Unavailable','Monitor publication failed: %s',err.message);
end
end
