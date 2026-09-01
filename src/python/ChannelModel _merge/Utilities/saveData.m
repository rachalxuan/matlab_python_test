function saveData(H_Martix_t,P_nMode,tao_nMode,doppler,LdB,all_cumulative_distances,outDataFolder,antennaPatternName,modelType,m,n)

% modelType = parameter.channel_standard;

for j = 1:n
    H_Martix_tMode = H_Martix_t(:,:,j);
    outpath = fullfile(outDataFolder,sprintf('%s_%d',antennaPatternName{j},m));
    switch modelType
        case 1
            save(outpath,'H_Martix_tMode', 'LdB','-v7');
        case {2, 3, 5}
            save(outpath, 'H_Martix_tMode', 'tao_nMode', 'P_nMode', 'LdB', 'doppler','-v7');
        case 4
            save(outpath, 'H_Martix_tMode', 'all_cumulative_distances', 'LdB','-v7');
        case {8, 6, 7}
            save(outpath, 'H_Martix_tMode', 'LdB', 'doppler','-v7');
        otherwise
            error('不支持的信道模型编号：%g', modelType);
    end
    % save(outpath,"H_Martix_tMode","tao_nMode","P_nMode","doppler");
end
end