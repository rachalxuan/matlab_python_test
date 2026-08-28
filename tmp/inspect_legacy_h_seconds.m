% Inspect whether each legacy H MAT file remains non-degenerate after 1 s.
files = { ...
    'std2_TDL',      'E:/matlab_project/v3.0/v3.0/channel/2-ChannelData.mat'; ...
    'std3_CDL',      'E:/matlab_project/v3.0/v3.0/channel/3-ChannelData.mat'; ...
    'std4_ITU_P681', 'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'; ...
    'std5_Jakes',    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_5.mat'; ...
    'std6_CLoo',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_6.mat'; ...
    'std7_Corazza',  'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'; ...
    'std8_Lutz',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_8.mat'};

fprintf('name,second,paths,samples,median_dB,min_dB,max_dB,zero_pct,unique_1e6,median_doppler_Hz\n');
for iFile = 1:size(files,1)
    s = load(files{iFile,2});
    if isfield(s,'H_Martix_tMode')
        H = double(s.H_Martix_tMode);
    else
        H = double(s.H_Matrix_tMode);
    end
    if ndims(H) < 3
        H = reshape(H,size(H,1),size(H,2),1);
    end
    nPath = size(H,1);
    nPerSecond = size(H,2);
    nSecond = size(H,3);
    for iSecond = 1:nSecond
        C = H(:,:,iSecond);
        if isfield(s,'P_nMode') && ~isempty(s.P_nMode)
            P = double(s.P_nMode);
            if isvector(P)
                if nPath == 1 && numel(P) >= iSecond
                    pNow = P(iSecond);
                elseif numel(P) >= nPath
                    pNow = P(1:nPath).';
                else
                    pNow = zeros(nPath,1);
                end
            elseif size(P,2) >= iSecond
                pNow = P(:,iSecond);
            else
                pNow = P(:,end);
            end
            pNow = pNow(:);
            if numel(pNow) == nPath
                C = C .* repmat(10.^(pNow/20),1,nPerSecond);
            end
        end
        mag = abs(C(:));
        magDB = 20*log10(max(mag,realmin));
        zeroPct = 100*mean(mag < 1e-12);
        uniqueRounded = numel(unique(round(real(C(:))*1e6) + 1j*round(imag(C(:))*1e6)));
        [~,dom] = max(mean(abs(C).^2,2));
        cd = C(dom,:);
        medMag = median(abs(cd));
        usable = abs(cd(1:end-1)) > 0.1*max(medMag,eps) & ...
                 abs(cd(2:end)) > 0.1*max(medMag,eps);
        dphi = angle(cd(2:end).*conj(cd(1:end-1)));
        dphi = dphi(usable & isfinite(dphi));
        if isempty(dphi)
            fd = NaN;
        else
            fd = median(dphi)*nPerSecond/(2*pi);
        end
        fprintf('%s,%d,%d,%d,%.3f,%.3f,%.3f,%.6f,%d,%.3f\n', ...
            files{iFile,1},iSecond,nPath,nPerSecond,median(magDB), ...
            min(magDB),max(magDB),zeroPct,uniqueRounded,fd);
    end
end
