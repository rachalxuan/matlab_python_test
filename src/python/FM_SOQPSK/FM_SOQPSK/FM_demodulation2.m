%% 基于高倍采样，超前滞后判决反馈的方案
% function N_errorbit=FM_demodulation2(fd,fs,fdoppler,N_per_frame,N_frame,r_cos_factor,TZZS,SNR,show_figure)

clc
close all
clear all

fd=20e6;
% fs=80e6;
fs=fd*32;
% fdoppler=0e3;
fdoppler=2e6;
show_figure=1;
N_per_frame=20000;
N_frame=1;
r_cos_factor=0.5;
% TZZS=0.715;%调制指数
TZZS=0.5;
% TZZS=0.35;
SNR=10;


data_sourse=randn(N_frame,N_per_frame)>0;%源数据
FM_Datamodule=FM_modulation(data_sourse,fd,fs,fdoppler,N_frame,N_per_frame,r_cos_factor,TZZS,show_figure);

%收发双方已知的训练序列
load data_training data_training;
FM_match_filter=data_training*2-1;
N_training=length(data_training);

%% 加噪声
interN=fs/fd;
Tx_Sig = awgn(FM_Datamodule,SNR,'measured');
noise = Tx_Sig-FM_Datamodule;
n0=mean(sqrt(noise.^2));
Tx_Sig=[n0*randn(1,10*interN),Tx_Sig,n0*randn(1,5*interN)];
L=length(Tx_Sig);
% Tx_Sig=FM_Datamodule;

% Tx_Sig=Tx_Sig*2^4;

%% 匹配滤波器（根升余弦，与发送端一致）
ShapingFilter=rcosine(fd,fs,'sqrt',r_cos_factor);
ShapingFilter=ShapingFilter/sum(ShapingFilter);
data_pipei_reg=zeros(1,length(ShapingFilter));
% 
% bt=3000;  %0.005 0.000005 0.00001  2000
% bt=0.0008;
% c1=8/3*bt;

% bt=3000*2^10;  %0.005 0.000005 0.00001  2000
% c1=8/3*bt;
c1=0.0002;
% c1=2^31*0.01
% c1=2^14;
% c2=32/9*bt*bt;
% c1=round(c1*2^31)
% c2=round(c2*2^31)
N=floor(length(Tx_Sig)/interN);
Ns=interN*N;  %总的采样点数
% lf_out=[2^30,zeros(1,N-1)];  %环路滤波器输出寄存器，初值设为0.5
% nco=[2^31*0.75,2^31*0.75,2^31*0.75,zeros(1,Ns-3)]; %NCO寄存器，初值设为0.9
% nco_temp=[nco(1),zeros(1,Ns-1)]; 
% fra_space=zeros(1,2*N);%NCO输出的定时分数间隔寄存器，初值设为0.6
% intet=zeros(1,2*N);       %内插后的输出数据 
% time_error=zeros(1,N); %Gardner提取的时钟误差寄存器
% ik=time_error;    %内插后的数据 
% intet=zeros(1,2*N);       %I路内插后的输出数据 
k=1;    %用来表示Ti时间序号,指示u,intet_i,intet_q
ms=1;   %用来指示T的时间序号,用来指示a,b以及w
inter_flag=zeros(1,Ns);
DataBase_r=zeros(1,interN);
N_chafen=1;
ns=length(Tx_Sig)-2;
ii=4;
phase=0;
delt_phase=0;
M_adapt=10;
k=1;
% addr(1)=round(rand(1)*32)+1;
addr(1)=1;
TS(1)=64;p=1;mean_data(1)=0;
Datajiance_reg=zeros(1,N_training+M_adapt);
y_reg=zeros(1,16);
Datamix(1)=0;
Database(1)=0;
nn=1;
ii=2;
% y(1)=1;locked=0;loc=1;loc_nn=1;
find_data_head=0;frame_find_flag=0;
cnt_valid=1;
cnt_frame=0;
temp=zeros();
temp_cnt=1;
intet_cur=0;
intet_pr=0;
m=0;dm=1/interN;

while(ii<ns)
    %% 混频（此处假设AD9361中集成的数字电路已将镜像频谱滤除，期望中频为0，仅剩下多普勒频差）
    phase=phase+delt_phase;%纠正残留频差
    Datamix(ii)=Tx_Sig(ii)*exp(-j*phase);%如果是实数，混频之后需要加低通，
    
    %% 差分
    DataBase_r(1:end-1)=DataBase_r(2:end);
    if(ii>N_chafen)
        DataBase_r(end)=angle(Datamix(ii))-angle(Datamix(ii-N_chafen));
    else
        DataBase_r(end)=0;
    end
%     DataBase_r(end)=mod(DataBase_r(end)+pi,2*pi)-pi;
    
    if(DataBase_r(end)>pi)
        DataBase_r(end)=DataBase_r(end)-2*pi;
    elseif(DataBase_r(end)<-pi)
        DataBase_r(end)=DataBase_r(end)+2*pi;
    else
    end
%     DataBase(ii)=sum(DataBase_r(end-interN+1:N_chafen:end));
    DataBase(ii)=DataBase_r(end)*32;
    
    %% 匹配滤波
    data_pipei_reg=[data_pipei_reg(2:end),DataBase(ii)];
    data_pipei(ii)=data_pipei_reg*ShapingFilter';

    %% 位同步   
    if(m>1)
        m=m-1;
        intet_cur=data_pipei(ii);
        a=(intet_cur+intet_pr)/2;
        time_error=[data_pipei(ii-interN/2)-a ]  *(sign(intet_cur)-sign(intet_pr));
        dm=1/interN + c1*time_error;
        if(dm>1/(interN-2) )
            dm=1/(interN-2)
        elseif(dm<1/(interN+2))
            dm=1/(interN+2)
        end
        intet_pr=intet_cur;
        
        addr(k)=ii;
        mid(k)=ii-interN/2;
        best_sample(k)=intet_cur;
        k=k+1;
     
        
       %% 相关检测
        Datajiance_reg=[Datajiance_reg(2:end),intet_cur];
        cor_result_comp(2*M_adapt+1)=abs((Datajiance_reg(end-N_training+1:end)-mean(Datajiance_reg(end-N_training+1:end)))*FM_match_filter');
        for ss=1:2*M_adapt
            cor_result_comp(ss)=cor_result_comp(ss+1);
        end
        %自适应门限
%             cor_result_i(ms)=cor_result_comp(2*M_adapt+1);
%             if(ms>(2*M_adapt+1))
%                 front_adder = sum(cor_result_i(ms-M_adapt+1:ms));
%                 backend_adder = sum(cor_result_i(ms-(2*M_adapt+1)+1:ms-(M_adapt+1)));
%                 total_adder = front_adder + backend_adder;
%                 self_adp_gate = total_adder*0.3;
%             else
%                 self_adp_gate =10;
%             end
        self_adp_gate=TZZS*100;%固定门限
        cor_result(ms)=cor_result_comp(M_adapt);
        self_adp_gate_save(ms)=self_adp_gate;

        %% 解调
        if(frame_find_flag)
            q=q+1;
            if(find_data_head)
                if(p>(N_per_frame))
                    frame_find_flag=0;
                    find_data_head=0;
                    p=1;
                else
                    output(cnt_valid)=intet_cur>0;
                    p=p+1;
                    cnt_valid=cnt_valid+1;
                end
            else
                p=1;
            end

            y_reg=[y_reg(2:end),intet_cur>0];
            if(sum(abs(y_reg-data_training(end-16+1:end)))==0  && (q<60))%规定时间内找到数据帧头，则开始有效接收数据；
                find_data_head=1;
                find_data_loc(cnt_frame+1)=ms;
            end
            if(q>60 && find_data_head==0)%规定时间内没有找到数据帧头，则认为这帧无效，重新检测
                frame_find_flag=0;
            end
        else
            find_data_head=0;
            p=1;q=1;
%                 delt_phase=0;
        end

        %峰值判决
        if(cor_result_comp(M_adapt)>self_adp_gate && ~frame_find_flag)
            %频偏估计
            delt_phase=delt_phase+mean(Datajiance_reg(1:N_training))/interN;
%                 delt_phase/2/pi*fs
            frame_find_flag=1;
            ii=ii-(N_training+M_adapt)*interN;%返回到训练序列之前，让训练序列重新进入
            cnt_frame=cnt_frame+1;
            frame_loc(cnt_frame)=ms;
%             nco(ii)=0.25*2^31;
        end

        frame_find_flag_save(ms)=frame_find_flag;
        ms=ms+1;
    end
    
    m=m+dm;
	
    ii=ii+1;
end

N_errorbit=sum(abs(output-reshape(data_sourse.',1,[])));

if(show_figure)
    figure;plot(DataBase,'-sb')
    figure;plot(data_pipei(2:4:end),'-sb')
%     figure;plot(ik,'-or');grid on;
    figure;histogram(best_sample(100:end-10),200);
%     figure;plot(time_error);grid on;
%     figure;plot(lf_out);grid on;
    figure;plot(self_adp_gate_save,'--r');grid on;
    hold on;plot(cor_result);grid on;
    legend('检测门限','相关峰值');
    hold on;plot(frame_loc,30*ones(size(frame_loc)),'sm');
    hold on;plot(40*frame_find_flag_save,'-g');
    hold on;plot(find_data_loc,30*ones(size(find_data_loc)),'or');
    
    disp(strcat('错误个数:',num2str(N_errorbit)));
    figure;plot(abs(output-reshape(data_sourse.',1,[])))
    
%     figure;plot(temp_r);
%     figure;plot(mod(nco/2^31+0.25,1)-0.25);
    figure;plot(addr,best_sample,'or');
    hold on;plot(data_pipei,'-b');
    
    
end

