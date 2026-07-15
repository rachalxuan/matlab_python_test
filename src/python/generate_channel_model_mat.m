function outFile = generate_channel_model_mat(channelParams, outFile, varargin)
%GENERATE_CHANNEL_MODEL_MAT Build a ChannelModel H-matrix file for CCSDS tests.
%
% outFile = generate_channel_model_mat(channelParams, outFile)
%
% This is a thin wrapper around:
%   E:\matlab_project\v3.0\v3.0\ChannelModel\ChannelModel
%
% The original ChannelModel main.m writes one .mat file per snapshot into
% OutData. This helper combines those snapshots into one file containing
% H_Martix_tMode, tao_nMode, P_nMode, doppler, and LdB, which is the format
% consumed by run_ccsds_tm_evaluation(..., 'HMode','h_matrix_file', ...).

    if nargin < 1 || isempty(channelParams)
        error('generate_channel_model_mat:MissingParams', ...
            'channelParams struct is required.');
    end
    if nargin < 2 || isempty(outFile)
        outFile = fullfile('E:\matlab_project\v3.0\v3.0\channel', ...
            'ChannelData_generated.mat');
    end

    ip = inputParser;
    ip.addParameter('ChannelModelRoot', ...
        'E:\matlab_project\v3.0\v3.0\ChannelModel\ChannelModel', ...
        @(x)ischar(x) || isstring(x));
    ip.addParameter('AntennaIndex', 1, @(x)isnumeric(x) && isscalar(x) && x >= 1);
    ip.addParameter('CleanOutData', true, @(x)islogical(x) || isnumeric(x));
    ip.addParameter('EnableSocket', false, @(x)islogical(x) || isnumeric(x));
    ip.addParameter('ApplyLdBToH', false, @(x)islogical(x) || isnumeric(x));
    ip.parse(varargin{:});

    channelModelRoot = char(ip.Results.ChannelModelRoot);
    antennaIndex = round(double(ip.Results.AntennaIndex));
    cleanOutData = logical(ip.Results.CleanOutData);
    enableSocket = logical(ip.Results.EnableSocket);
    applyLdBToH = logical(ip.Results.ApplyLdBToH);

    if exist(channelModelRoot, 'dir') ~= 7
        error('generate_channel_model_mat:MissingChannelModelRoot', ...
            'ChannelModelRoot not found: %s', channelModelRoot);
    end

    oldDir = pwd;
    cleanupObj = onCleanup(@() cd(oldDir)); %#ok<NASGU>
    cd(channelModelRoot);
    addpath(genpath(channelModelRoot));

    parameter = getParameters(channelParams, channelModelRoot);
    if isfield(parameter, 'socket')
        parameter.socket.enable = enableSocket;
    end
    outDataFolder = char(parameter.outDataFolder);
    if cleanOutData && exist(outDataFolder, 'dir') == 7
        rmdir(outDataFolder, 's');
    end
    if exist(outDataFolder, 'dir') ~= 7
        mkdir(outDataFolder);
    end

    [t_vec, termPosRange, satPosRange, satVelRange, Angles, fd_record] = ...
        TrajectoryEngine(parameter);
    selectModel_Interface(parameter, t_vec, satPosRange, termPosRange, ...
        satVelRange, Angles, fd_record);

    files = localSelectOutDataFiles(outDataFolder, parameter, antennaIndex);
    if isempty(files)
        error('generate_channel_model_mat:NoOutDataFiles', ...
            'No generated .mat files found in %s for antenna index %d.', ...
            outDataFolder, antennaIndex);
    end

    combined = localCombineOutData(files);
    H_Martix_tMode = combined.H_Martix_tMode;
    if applyLdBToH
        if ~isfield(combined, 'LdB')
            error('generate_channel_model_mat:MissingLdB', ...
                'ApplyLdBToH=true but generated OutData has no LdB field.');
        end
        H_Martix_tMode = localApplyLdBToH(H_Martix_tMode, combined.LdB);
    end
    H_Martix_tMode = H_Martix_tMode; %#ok<NASGU>

    saveVars = {'H_Martix_tMode'};
    if isfield(combined, 'LdB')
        LdB = combined.LdB; %#ok<NASGU>
        saveVars{end+1} = 'LdB'; %#ok<AGROW>
    end
    if isfield(combined, 'P_nMode')
        P_nMode = combined.P_nMode; %#ok<NASGU>
        saveVars{end+1} = 'P_nMode'; %#ok<AGROW>
    end
    if isfield(combined, 'tao_nMode')
        tao_nMode = combined.tao_nMode; %#ok<NASGU>
        saveVars{end+1} = 'tao_nMode'; %#ok<AGROW>
    end
    if isfield(combined, 'doppler')
        doppler = combined.doppler; %#ok<NASGU>
        saveVars{end+1} = 'doppler'; %#ok<AGROW>
    end
    if isfield(combined, 'all_cumulative_distances')
        all_cumulative_distances = combined.all_cumulative_distances; %#ok<NASGU>
        saveVars{end+1} = 'all_cumulative_distances'; %#ok<AGROW>
    end

    ChannelModelMeta = struct(); %#ok<NASGU>
    ChannelModelMeta.ChannelModelRoot = channelModelRoot;
    ChannelModelMeta.OutDataFolder = outDataFolder;
    if isfield(channelParams, 'channel_standard')
        ChannelModelMeta.ChannelStandard = string(channelParams.channel_standard);
    else
        ChannelModelMeta.ChannelStandard = "1";
    end
    ChannelModelMeta.AntennaIndex = antennaIndex;
    ChannelModelMeta.SourceFiles = string({files.name});
    ChannelModelMeta.SampleRateHz = getfieldnumeric_local(channelParams, ...
        'sample_rate', size(H_Martix_tMode, 2));
    ChannelModelMeta.ApplyLdBToH = applyLdBToH;
    saveVars{end+1} = 'ChannelModelMeta';

    outFolder = fileparts(outFile);
    if ~isempty(outFolder) && exist(outFolder, 'dir') ~= 7
        mkdir(outFolder);
    end
    save(outFile, saveVars{:}, '-v7');
    fprintf('Saved combined channel file: %s\n', outFile);
    fprintf('H_Martix_tMode size: [%s]\n', num2str(size(H_Martix_tMode)));
end

function files = localSelectOutDataFiles(outDataFolder, parameter, antennaIndex)
    names = cellstr(parameter.antennaPatternName);
    if antennaIndex > numel(names)
        error('generate_channel_model_mat:BadAntennaIndex', ...
            'AntennaIndex=%d exceeds available antenna files=%d.', ...
            antennaIndex, numel(names));
    end
    antennaName = names{antennaIndex};
    raw = dir(fullfile(outDataFolder, [antennaName, '_*.mat']));

    oneSuffix = ['^', regexptranslate('escape', antennaName), '_(\d+)\.mat$'];
    twoSuffix = ['^', regexptranslate('escape', antennaName), '_', ...
        num2str(antennaIndex), '_(\d+)\.mat$'];

    keep = false(numel(raw), 1);
    order = zeros(numel(raw), 1);
    for k = 1:numel(raw)
        tok = regexp(raw(k).name, oneSuffix, 'tokens', 'once');
        if isempty(tok)
            tok = regexp(raw(k).name, twoSuffix, 'tokens', 'once');
        end
        if ~isempty(tok)
            keep(k) = true;
            order(k) = str2double(tok{1});
        end
    end
    files = raw(keep);
    order = order(keep);
    [~, idx] = sort(order);
    files = files(idx);
end

function combined = localCombineOutData(files)
    combined = struct();
    for k = 1:numel(files)
        s = load(fullfile(files(k).folder, files(k).name));
        if ~isfield(s, 'H_Martix_tMode')
            error('generate_channel_model_mat:MissingH', ...
                'Missing H_Martix_tMode in %s.', files(k).name);
        end

        Hk = double(s.H_Martix_tMode);
        if ndims(Hk) > 2
            Hk = reshape(Hk, size(Hk, 1), size(Hk, 2), []);
            Hk = Hk(:, :, 1);
        end
        if k == 1
            combined.H_Martix_tMode = complex(zeros(size(Hk, 1), size(Hk, 2), numel(files)));
        end
        combined.H_Martix_tMode(:, :, k) = Hk;

        combined = localAppendField(combined, s, 'LdB', k, numel(files));
        combined = localAppendField(combined, s, 'P_nMode', k, numel(files));
        combined = localAppendField(combined, s, 'tao_nMode', k, numel(files));
        combined = localAppendField(combined, s, 'doppler', k, numel(files));
        combined = localAppendField(combined, s, 'all_cumulative_distances', k, numel(files));
    end
end

function combined = localAppendField(combined, s, fieldName, k, nFiles)
    if ~isfield(s, fieldName)
        return;
    end
    value = double(s.(fieldName));
    if isempty(value)
        return;
    end
    value = value(:);
    if ~isfield(combined, fieldName)
        combined.(fieldName) = zeros(numel(value), nFiles);
    end
    n = min(size(combined.(fieldName), 1), numel(value));
    combined.(fieldName)(1:n, k) = value(1:n);
end

function H = localApplyLdBToH(H, LdB)
    nSec = size(H, 3);
    lossDb = double(LdB);

    if isscalar(lossDb)
        lossVec = repmat(lossDb, 1, nSec);
    elseif isvector(lossDb) && numel(lossDb) == nSec
        lossVec = reshape(lossDb, 1, []);
    elseif size(lossDb, 2) == nSec
        lossVec = lossDb(1, :);
    elseif size(lossDb, 1) == nSec
        lossVec = reshape(lossDb(:, 1), 1, []);
    else
        error('generate_channel_model_mat:BadLdBShape', ...
            'Cannot map LdB size [%s] to H seconds=%d.', num2str(size(lossDb)), nSec);
    end

    scale = 10.^(-lossVec / 20);
    scale(~isfinite(scale)) = 0;

    for idx = 1:nSec
        H(:, :, idx) = H(:, :, idx) .* scale(idx);
    end
end

function value = getfieldnumeric_local(s, fieldName, defaultValue)
    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        value = double(s.(fieldName));
    else
        value = defaultValue;
    end
end
