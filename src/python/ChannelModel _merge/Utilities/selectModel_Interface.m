function selectModel_Interface(parameter, t_vec, satPosRange, termPosRange, satVelRange, Angles, fd_record,traj)
% function [LdB, H_Martix_tMode, tao_nMode, P_nMode, doppler,all_cumulative_distances] = selectModel_Interface(parameter, t_vec, satPosRange, termPosRange, satVelRange, Angles, fd_record)
        tao_nMode = complex([]); P_nMode = []; H_Martix_tMode = complex([]); doppler = [];all_cumulative_distances = [];
        N_snapshots = length(t_vec); nextProgressIdx = 2;
        % LdB = zeros(1, N_snapshots); 
        LdB = [];  
        parameter.current_global_distance = 0;
        % actualSnapshots = N_snapshots; 
        position = struct(); 
        position.terminalVelocity = parameter.terminalVelocity;
        
        % position.terminalX = termPosRange(1, 1); position.terminalY = termPosRange(2, 1); position.terminalZ = termPosRange(3, 1);
        % position.satelliteX = satPosRange(1, 1); position.satelliteY = satPosRange(2, 1); position.satelliteZ = satPosRange(3, 1);
        % position.Rsatellite = norm(satPosRange(:, 1));
        % position.satelliteVelocity = satVelRange(:, 1);
        modelType = parameter.channel_standard;
        [~,Mincommunicationangle] = find(Angles.EOA <= parameter.minElevation,1);
        if N_snapshots > Mincommunicationangle
            N_snapshots = Mincommunicationangle;
        end
        if N_snapshots > 600 && ~parameter.is_quick_simulation
            N_snapshots = 600;
        elseif parameter.is_quick_simulation
             N_snapshots = 1;
        end
        numsend = 0;
        if parameter.is_quick_simulation
           send([num2str((10))], parameter.socket); 
        end
        % if ((parameter.fc >= 2 && parameter.fc <= 4) || (parameter.fc >= 26.5 && parameter.fc <= 40))
               if (parameter.channelMod == 'A' || parameter.channelMod == 'C') && (parameter.encdl ||parameter.entdl) 
                   clusterNum = 3 - (parameter.entdl && parameter.channelMod == 'C' ); 
               elseif (parameter.encdl ||parameter.entdl)
                   clusterNum = 4 - (parameter.channelMod == 'D' && parameter.entdl);
               elseif parameter.CustomMultipath
                   clusterNum = parameter.nPaths;
               else
                   clusterNum = 1;
               end
               % H_Martix_tMode = complex(zeros(clusterNum, parameter.N_Ts, N_snapshots)); tao_nMode = zeros(clusterNum, N_snapshots); P_nMode = zeros(clusterNum, N_snapshots);
               H_Martix_tMode = complex(zeros(clusterNum, parameter.N_Ts)); tao_nMode = zeros(clusterNum,1); P_nMode = zeros(clusterNum, 1);
               for i = 1:parameter.dT:N_snapshots
                    % if isequal(btnPause.UserData, true), actualSnapshots = max(1, i-1); break; end
                    % if mod(i, 5) == 0, drawnow limitrate; end 
                    % actualSnapshots = max(1, i-1);
                    position.terminalX = termPosRange(1,i); position.terminalY = termPosRange(2,i); position.terminalZ = termPosRange(3,i);
                    position.satelliteX = satPosRange(1,i); position.satelliteY = satPosRange(2,i); position.satelliteZ = satPosRange(3,i); 
                    position.satelliteVelocity = satVelRange(:,i); position.satellite = sqrt(sum(position.satelliteVelocity.^2));
                    position.losEOA = Angles.EOA(i); 
                    EOA = position.losEOA;
                    data = parameter.antennaGainData;
                    % if ~parameter.encdl
                    [field,Gain] = GenerateAntennaPattern_Gain([0,EOA,0],EOA+90,0,data); parameter.GainTx = Gain; parameter.GainRx = 1;
                    parameter.NumAntennaPattern = size(field,2);
                    parameter.F_tx = reshape(field,2,1,1,parameter.NumAntennaPattern);
                    parameter.satelliteHeight = traj.SelectedAlt(i)*1e3;
                    % end
                    if EOA < parameter.minElevation
                        % Loss = NaN; H_Martix_tMode(:,:,i) = 0; tao_nMode(:,i) = 0; P_nMode(:,i) = 0;
                        Loss = NaN; H_Martix_tMode(:,:) = 0; tao_nMode(:,1) = 0; P_nMode(:,1) = 0;
                    else
                        % [H_Martix_t,tao_n,P_n,dopplercent] = CDLModel(parameter,position); H_Martix_tMode(:,:,i) = H_Martix_t; tao_nMode(:,i) = tao_n; P_nMode(:,i) = P_n;
                        if mod(i-1,30) ==0  || parameter.is_quick_simulation
                        Loss = 0;
                        if parameter.enFSPL, tmp = freeSpacePathLoss(parameter, EOA); if ~isempty(tmp), Loss = Loss + tmp(1); end; end
                        if parameter.enAtmo, tmp = atmosphericAttenuation(parameter, EOA); if ~isempty(tmp), Loss = Loss + tmp(1); end; end
                        if parameter.enRain, tmp = rainFallLoss(parameter,EOA); if ~isempty(tmp), Loss = Loss + tmp(1); end; end
                        if parameter.enCloud, tmp = cloudLoss(parameter, EOA); if ~isempty(tmp), Loss = Loss + tmp(1); end; end
                        if parameter.enTropo, tmp = troposphericScintillationLoss(parameter, EOA); if ~isempty(tmp), Loss = Loss + tmp(1); end; end
                        if parameter.enIono, tmp = ionosphericScintillation(parameter,EOA); if ~isempty(tmp), Loss = Loss + tmp(1); end; end
                        if parameter.enBeam, Loss = Loss + beamSpreadingLoss(EOA); end
                        if parameter.enShadow || parameter.enClutter
                            [SF, CL] = shadowFadingClutterLoss(parameter, EOA, 1);
                            if parameter.enShadow && ~isempty(SF), Loss = Loss + SF(1); end
                            if parameter.enClutter && ~isempty(CL), Loss = Loss + CL(1); end
                        end
                        if parameter.enPol
                            Loss = Loss + 3.0;
                        end
                        end
                        LdBLinear = sqrt(10^(-Loss/10));

                        if parameter.is_quick_simulation
                           send([num2str((30))], parameter.socket); 
                        end

                        if parameter.encdl
                            % for j = 1:size(parameter.antennaGainData,1)
                            %     parameter.antennaGain = parameter.antennaGainData(j);
                            %     [H_Martix_t,tao_n,P_n,dopplercent] = CDLModel(parameter,position); 
                            %     H_Martix_tMode(:,:) = H_Martix_t * LdBLinear; 
                            %     tao_nMode = tao_n'; 
                            %     P_nMode = P_n';
                            %     doppler = dopplercent;
                            %     outpath = fullfile(parameter.outDataFolder,sprintf('%s_%d_%d',parameter.antennaPatternName{j},j,i));
                            %     save(outpath,"H_Martix_tMode","tao_nMode","P_nMode","doppler");
                            % end
                                [H_Martix_t,tao_n,P_n,dopplercent] = CDLModel(parameter,position); 
                                H_Martix_tMode = H_Martix_t * LdBLinear; 
                                tao_nMode = tao_n'; 
                                P_nMode = P_n';
                                doppler = dopplercent;
                        end

                        if parameter.CustomMultipath
                            sat = sqrt(sum(position.satelliteVelocity.^2));
                            if parameter.IsLos 
                               vectorLosPath= [sind(Angles.ZOD(i)) * cosd(Angles.AOD(i)); ...                 % LoS射线矢量
                                               sind(Angles.ZOD(i)) * sind(Angles.AOD(i)); ...
                                               cosd(Angles.ZOD(i))];
                               costheta = sum(vectorLosPath .* position.terminalVelocity)/sqrt(sum(position.terminalVelocity.^2)); 
                            end
                            [H_Martix_t,fd_shift,tao] = generateJakesSpec(parameter,sat,EOA,costheta);
                            H_Martix_tMode = LdBLinear * H_Martix_t;
                            doppler = fd_shift;
                            P_nMode = parameter.power_dB*ones(size(tao));
                            tao_nMode = tao;
                        end
                        if parameter.entdl
                            [H_Martix_t,tao_n,P_n,dopplercent] = TDLModel(parameter,position); 
                            % H_Martix_tMode(:,:,i) = H_Martix_t * LdBLinear; 
                            H_Martix_tMode = H_Martix_t * LdBLinear;
                            tao_nMode = tao_n; 
                            P_nMode = P_n;
                            doppler = dopplercent;
                        end

                        if parameter.enCLoo || parameter.enCorazza || parameter.enLutz
                            fs = parameter.Fs; T = parameter.T; fc = parameter.fc*1e9;
                            mu_dB =  parameter.mu_dB; sigma_dB = parameter.sigma_dB;sigma0 = parameter.sigma0;
                            v = parameter.terminalVel; R= parameter.Re; h = parameter.satelliteHeight;
                            fd_shift = (position.satellite/parameter.c) * (R/(R+h)) * cosd(EOA) * fc;
                            K_linear = parameter.K_linear;
                            manual_state = parameter.manual_state;
                            dopplerPhaseVector = GeneratedopplerPhase(fs,fd_shift,fs*T);

                            vectorLosPath= [sind(Angles.ZOD(i)) * cosd(Angles.AOD(i)); ...                 % LoS射线矢量
                                            sind(Angles.ZOD(i)) * sind(Angles.AOD(i)); ...
                                            cosd(Angles.ZOD(i))];
                            costheta = sum(vectorLosPath .* position.terminalVelocity)/sqrt(sum(position.terminalVelocity.^2)); 
                            if parameter.enCLoo
                                H_matrix = CLoo(fs,T,fc,v,mu_dB,sigma_dB,sigma0,costheta);
                            end
                            if parameter.enCorazza
                            H_matrix = Corazza(fs,T,fc,v,mu_dB,sigma_dB,K_linear,costheta);
                            end
                            if parameter.enLutz
                            H_matrix = Lutz(fs,T,fc,v,mu_dB,sigma_dB,K_linear,manual_state,costheta);
                            end
                            
                            for j = 1:size(parameter.GainTx,2)
                            H_Martix_tMode(:,:,j) = LdBLinear*parameter.GainTx(j)*H_matrix.*dopplerPhaseVector *parameter.GainRx;
                            end
                            doppler = fd_shift;
                        end
                        if parameter.ITU_R
                        % if isequal(btnPause.UserData, true), actualSnapshots = max(1, i-1); break; end
                        % if mod(i, 5) == 0, drawnow limitrate; end 
                        % actualSnapshots = max(1, i-1);
                        fc_Hz = parameter.fc * 1e9; theta_init = Angles.EOA(i); environment = parameter.environment;
                        if fc_Hz >= 1.5e9 && fc_Hz <= 5e9
                            switch environment
                                case {1,2,3,4} 
                                    if theta_init < 25, roundedElevation = 20; 
                                    elseif theta_init < 37.5, roundedElevation = 30; 
                                    elseif theta_init < 52.5, roundedElevation = 45; 
                                    elseif theta_init < 65, roundedElevation = 60; 
                                    else, roundedElevation = 70;
                                    end
                                case 5
                                    if theta_init < 25, roundedElevation = 20; 
                                    elseif theta_init < 45, roundedElevation = 30; 
                                    elseif theta_init < 65, roundedElevation = 60; 
                                    else, roundedElevation = 70; 
                                    end
                                otherwise, error("Invalid Environment");
                            end
                        elseif fc_Hz >= 10e9 && fc_Hz <= 20e9
                                switch environment
                                    case {6,1,7}
                                        roundedElevation = 30; 
                                    case 8
                                        roundedElevation = 34; 
                                    case 2 
                                        if fc_Hz < 15.85e9, roundedElevation = 34; 
                                        else, roundedElevation = 30; 
                                        end
                                    otherwise, error("Invalid Environment");
                                end
                        else
                                error("Invalid Carrier Frequency"); 
                        end
                        if i == 1
                            parameter.roundedElevation = roundedElevation;
                            parameter.Tt = 0;
                            parameter.keeptimes = 0;
                        end
                        if parameter.is_quick_simulation
                            numsend = 50;
                        end

                        if ~isequal(parameter.roundedElevation,roundedElevation)&& i ~=1 || i == N_snapshots
                            parameter.Tt = i - parameter.keeptimes;
                            parameter.keeptimes = i;
                            parameter.roundedElevation = roundedElevation;
                            [all_cumulative_distances,H_Martix_,numsend] = doubleState681(parameter,position,numsend);
                            parameter.current_global_distance = all_cumulative_distances(end);
                            all_cumulative_distances = reshape(all_cumulative_distances,parameter.Tt,parameter.Fs);
                            H_Martix_t = [];
                        for j = 1:size(parameter.GainTx,2)
                            H_Martix_t(:,:,j) = LdBLinear*parameter.GainTx(j).*H_Martix_ *parameter.GainRx;
                        end
                        H_Martix_talltime = reshape(H_Martix_t,parameter.Tt,size(H_Martix_t,2)/parameter.Tt,size(H_Martix_t,3));
                        H_Martix_tMode = H_Martix_talltime(:,1:parameter.N_Ts,:);
                        LdB = Loss;
                        for m = i-parameter.Tt(end)+1 :i
                            saveData(H_Martix_tMode(m-(i-parameter.Tt),:,:),P_nMode,tao_nMode,doppler,LdB,all_cumulative_distances(m-(i-parameter.Tt),:),parameter.outDataFolder, ...
                            parameter.antennaPatternName,modelType,m,size(parameter.antennaGainData,1));

                            progressPercent = round(m / N_snapshots * 100); 
                            % times = round(100/(19 -numEvents));
                            
                            % progressPercent = round(DataCount / N_snapshots * 100);
                            while mod(progressPercent,10) == 0  && nextProgressIdx == floor (progressPercent/10) && nextProgressIdx <= 19 && numsend<=95 && progressPercent > 1
                                
                                  send([num2str(numsend)], parameter.socket);
                                  nextProgressIdx = nextProgressIdx + 1; 
                                  numsend = numsend+5;
                               
                            end
                        end

                        end
                        end
                    if parameter.is_quick_simulation && ~parameter.ITU_R
                       send([num2str((50))], parameter.socket); 
                    end
                    LdB = Loss ;
                    
                    if modelType ==1
                        H_Martix_tMode = ones(size(parameter.antennaGainData,1),parameter.N_Ts).*Gain'*LdBLinear*parameter.GainRx;
                        H_Martix_tMode = reshape(H_Martix_tMode',1,parameter.N_Ts,size(parameter.antennaGainData,1));
                    end

                    if  ~parameter.ITU_R
                        saveData(H_Martix_tMode,P_nMode,tao_nMode,doppler,LdB,all_cumulative_distances,parameter.outDataFolder,parameter.antennaPatternName,modelType,i,size(parameter.antennaGainData,1));
                    end

                    if i == 25
                        send([num2str((5))], parameter.socket);
                        
                        numsend = 10;
                    end

                    if ~parameter.ITU_R
                        progressPercent = round(i / N_snapshots * 100); 
                        
                        while mod(progressPercent,5) ==0 && nextProgressIdx == floor (progressPercent/5)&& nextProgressIdx <= 19
                          
                              send([num2str((progressPercent))], parameter.socket);
                              nextProgressIdx = nextProgressIdx + 1;
                      
                        end
                    end
                        if parameter.is_quick_simulation
                           send([num2str((80))], parameter.socket); 
                        end

                    end
               end

        % else
        %     error('3GPP 38.811 频率验证失败 (宽带仅支持 2-4GHz 或 26.5-40GHz)'); 
        % 
        % 
        % end
        while numsend ~= 100 && parameter.ITU_R && ~parameter.is_quick_simulation
              send([num2str((numsend))], parameter.socket); 
              numsend = numsend+5;
        end
end

function dopplerPhaseVector = GeneratedopplerPhase(fs,fd,N)
        dopplerPhase = 2*pi*(1/fs)*(fd).*(0:N)';
        dopplerPhaseVector = exp(-1j*dopplerPhase(1:(end-1),1))';
end