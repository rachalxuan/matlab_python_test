
function DataCount = main(channelParm)

projectRoot = fileparts(mfilename('fullpath'));

addpath(genpath(projectRoot));
addpath(genpath('external_data'));
addpath(genpath('LargeScale'));
addpath(genpath('smallScale'));
addpath(genpath('Utilities'));

parameter = getParameters(channelParm,projectRoot);

if parameter.channel_standard == 9
    % AWGN has no propagation-model output.  Do not delete an earlier custom
    % channel's OutData directory; Python owns cache invalidation per request.
    DataCount = 0;
    % Do not emit a zero-byte UDP path packet: Python represents the empty
    % address as an empty mat_file_paths list using channel_standard=9.
    send(100, parameter.socket);
    return;
end


folder = parameter.outDataFolder;
if exist(folder, 'dir')
    rmdir(folder, 's');
end
mkdir(folder);

[t_vec, termPosRange, satPosRange, satVelRange, Angles, fd_record,traj] = TrajectoryEngine(parameter);

% vSat = sqrt(sum(satVelRange.^2,1));
% theta = Angles.EOA;
% c = physconst('lightspeed'); 
% r = physconst('earthradius');
% h = traj.SelectedAlt*1e3;
% fdMaxUE = (parameter.terminalVel*parameter.fc*1e9)/c;
% fdSatMax = max((vSat*parameter.fc*1e9/c).*(r*cosd(theta)./(r+h')));
% % fdSatMax = ((vSat*parameter.fc*1e9/c).*(r*cosd(theta)./(r+h')));
% 
% if abs(fdSatMax)+fdMaxUE > parameter.Fs/2
%     fd = (abs(fdSatMax)+fdMaxUE)*2;
%     % if fd/1e5< 10 
%     %     SugFd = ceil(fd/1e5)*1e5;
%     % else
%     %     SugFd = ceil(fd/1e6)*1e6;
%     % end
%     if fd/1e5< 10 
%         if round(fd/1e5)/(fd/1e5) < 1
%           SugFd = (round(fd/1e5)+0.5)*1e5;
%         else
%           SugFd = round(fd/1e5)*1e5;
%         end
%     else
%         if round(fd/1e6)/(fd/1e6) < 1
%            SugFd = (round(fd/1e6)+0.5)*1e6;
%         else
%             SugFd = round(fd/1e6)*1e6;
%         end
%     end
% 
%     error("建议采样率最低设置为："+num2str(SugFd));
% end

selectModel_Interface(parameter, t_vec, satPosRange, termPosRange, satVelRange, Angles, fd_record,traj);

dirlist = dir(parameter.outDataFolder);
DataCount = (length(dirlist)-2)/length(parameter.antennaGainData);


send(parameter.outDataFolder,parameter.socket);
send(num2str((100)),parameter.socket);



end






