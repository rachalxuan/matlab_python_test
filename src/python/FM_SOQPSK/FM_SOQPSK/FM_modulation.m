function  FM_Datamodule=FM_modulation(data_sourse,fd,fs,fdoppler,N_frame,N_per_frame,r_cos_factor,TZZS,show_figure)

% clc
% close all
% clear all
% 
% fd=20e6;
% fs=160e6;
% fdoppler=40000e3;
% % fdoppler=20e6;
% show_figure=1;
% N_per_frame=1000;
% N_frame=1;
% r_cos_factor=0.7;
% TZZS=0.715;
% % TZZS=0.5;
% data_sourse=randn(N_frame,N_per_frame)>0;%源数据


%% 组帧
interN=fs/fd;
data_hs=randn(1,100)>0;%缓升序列
% data_training=[randn(1,48)>0];
% sum(data_training)
% save data_training data_training;

load data_training data_training;

data_send=data_hs;
for ii=1:N_frame
    data_send=[data_send,data_training,data_sourse(ii,:)];
end

%% 调制
database=data_send*2-1;%映射
database=upsample(database,fs/fd);%插值
ShapingFilter=rcosine(fd,fs,'sqrt',r_cos_factor);
ShapingFilter=ShapingFilter/sum(ShapingFilter);

DataLPF=conv(database,ShapingFilter);

for ii=1:length(DataLPF)
    if(ii>1)
        ps(ii)=ps(ii-1)+DataLPF(ii);
    else
        ps(ii)=0;
    end
end

% FM_Datamodule=exp(j*ps*pi*TZZS);
FM_Datamodule=exp(j*ps*pi*TZZS).*exp(j*2*pi*fdoppler/fs*[1:length(ps)]);

%% 绘图
if(show_figure)
    figure;plot(DataLPF);grid on;
    figure;plot(ps);
    figure;
    plot(real(FM_Datamodule));
    title('调制信号');
    
    fft_FM_Datamodule=abs(fft(FM_Datamodule));
    L=length(fft_FM_Datamodule);
    figure;plot([1:L]/L*fs,20*log10(fft_FM_Datamodule));grid on;
    title('FM调制信号频谱');
end



