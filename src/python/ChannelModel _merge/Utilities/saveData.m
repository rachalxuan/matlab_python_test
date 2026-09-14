function saveData(H_Martix_t,P_nMode,tao_nMode,doppler,LdB,all_cumulative_distances,outDataFolder,antennaPatternName,modelType,m,n,varargin)

% modelType = parameter.channel_standard;

for j = 1:n
    H_Martix_tMode = H_Martix_t(:,:,j);
    outpath = fullfile(outDataFolder,sprintf('%s_%d',antennaPatternName{j},m));

    % Persist the time-base contract beside every snapshot.  Older exports
    % omitted this information, forcing the receiver to guess that a 2-D
    % matrix was sampled at 100 kHz.  The final _<m> filename suffix is the
    % snapshot ordinal; antennaPatternName identifies a parallel antenna
    % realization and must not be concatenated with its siblings.
    channelSampleRateHz = NaN;
    channelSnapshotInterval_s = NaN;
    if ~isempty(varargin) && isstruct(varargin{1})
        parameter = varargin{1};
        if isfield(parameter,'Fs')
            channelSampleRateHz = double(parameter.Fs);
        end
        if isfield(parameter,'dT')
            channelSnapshotInterval_s = double(parameter.dT);
        end
    end
    channelSnapshotIndex = double(m);
    channelSnapshotStartTime_s = ...
        (channelSnapshotIndex - 1) * channelSnapshotInterval_s;
    if isfinite(channelSampleRateHz) && channelSampleRateHz > 0
        channelSnapshotDuration_s = ...
            size(H_Martix_tMode,2) / channelSampleRateHz;
    else
        channelSnapshotDuration_s = NaN;
    end
    channelSnapshotIsContiguous = isfinite(channelSnapshotDuration_s) && ...
        isfinite(channelSnapshotInterval_s) && ...
        abs(channelSnapshotDuration_s - channelSnapshotInterval_s) <= ...
        max(1e-12, 1e-9*max(channelSnapshotDuration_s,channelSnapshotInterval_s));
    channelAntennaPatternName = char(string(antennaPatternName{j}));
    channelModelType = double(modelType);
    ChannelModelMeta = struct( ...
        'SampleRateHz',channelSampleRateHz, ...
        'SnapshotIndex',channelSnapshotIndex, ...
        'SnapshotStartTime_s',channelSnapshotStartTime_s, ...
        'SnapshotDuration_s',channelSnapshotDuration_s, ...
        'SnapshotInterval_s',channelSnapshotInterval_s, ...
        'SnapshotIsContiguous',channelSnapshotIsContiguous, ...
        'AntennaPatternName',channelAntennaPatternName, ...
        'ChannelStandard',channelModelType);
    metadataVars = {'channelSampleRateHz','channelSnapshotIndex', ...
        'channelSnapshotStartTime_s','channelSnapshotDuration_s', ...
        'channelSnapshotInterval_s','channelSnapshotIsContiguous', ...
        'channelAntennaPatternName','channelModelType','ChannelModelMeta'};
    switch modelType
        case 1
            save(outpath,'H_Martix_tMode','LdB',metadataVars{:},'-v7');
        case {2, 3, 5}
            save(outpath,'H_Martix_tMode','tao_nMode','P_nMode','LdB','doppler',metadataVars{:},'-v7');
        case 4
            save(outpath,'H_Martix_tMode','all_cumulative_distances','LdB',metadataVars{:},'-v7');
        case {8, 6, 7}
            save(outpath,'H_Martix_tMode','LdB','doppler',metadataVars{:},'-v7');
        otherwise
            error('不支持的信道模型编号：%g', modelType);
    end
    % save(outpath,"H_Martix_tMode","tao_nMode","P_nMode","doppler");
end
end
