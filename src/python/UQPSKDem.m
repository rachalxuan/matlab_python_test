%% UQPSK解调程序

clear;
clc;
close all;

RRatio = 2	;	%I/Q速率比
ARatio = 2	;	%I/Q幅度比

Fs = 960	;	%采样率，单位MHz
Fd = 300   	;	%I支路传输速率，单位MBd，范围30至300
Fc = 240	;	%中频载波频率，单位MHz

load('D:\Design\MatlabWorks\UQPSK_modem\ModSig.mat');
% load('D:\Design\MatlabWorks\UQPSK_modem\ModSig_300MBd_20IQRatio.mat');
%%
%加噪
SNR = 10;
ModSig = awgn(ModSig,SNR,'measured');
%%
%下变频到基带I、Q数据

% pwelch(ModSig,[],[],[],Fs,'twosided');
DDCZ = ModSig.*exp(1j*2*pi*Fc/Fs*(1:length(ModSig)));
% pwelch(DDCZ,[],[],[],Fs,'twosided');

FIRLen = 512;

LPF = fir1(FIRLen-1,Fd/Fs*1.35);
% fvtool(LPF);
LPDZ = conv(LPF,DDCZ)*2;
% pwelch(LPDZ,[],[],[],Fs,'twosided');

if ( Fd > 119.5 )
    DSRate = 1;
elseif ( Fd > 59.75 )
    DSRate = 2;
elseif ( Fd > 29.875 )
    DSRate = 4;
end

RevZ = LPDZ(1:DSRate:end);


%%
%下采样 采样率变换，插值到符号速率的两倍，时钟恢复环路、载波恢复环路
Fs = Fs/DSRate;
% figure
% pwelch(RevZ,[],[],[],Fs,'twosided');


w_ctl =Fd*2/Fs;
w_ctl_pre = w_ctl;
nco = 1;
u_ctl = 0;

I_est_pre = 1;
Q_est_pre = -1;

uk = 0;
u0 = 0;
cnt = 0;

U_Cons = Fs/(Fd*2);

RevN = 1;

e0 = 0;
theta0 = 0;



for k = 512:length(RevZ)-100
    
    if nco -w_ctl < 0
        if cnt == 1
            cnt = 0;
            u_ctl = nco*U_Cons;

            Reg_interp = RevZ(k+2:-1:k-1)*exp(-j*theta0);
            I_est = InterpLag(real(Reg_interp),u_ctl); 
            Q_est = InterpLag(imag(Reg_interp),u_ctl);
            
            e = (sign(I_est_pre)-sign(I_est))* I_est_1_2 + (sign(Q_est_pre)-sign(Q_est)) * Q_est_1_2;   %时钟相位偏差提取
            uk = u0+e*4/4000;        
            u0 = u0+e*0.005/4000;    
            
            w_ctl_pre = w_ctl    ;
                   
            w_ctl = Fd*2/Fs - uk;
            
            e_theta = sign(I_est)*Q_est*ARatio-sign(Q_est)*I_est;   %载波相位偏差提取
    
            ek = e0+(e_theta)*1000;
            e0 = e0+(e_theta)*2;
            theta0 = theta0+ek/30000;
            
            I_est_pre = I_est;
            Q_est_pre = Q_est;
            
            IntpZ(RevN) = I_est + 1j*Q_est;
            RevN = RevN + 1 ;
            
        elseif cnt ==0
            Reg_interp_1_2 = RevZ(k+2:-1:k-1)*exp(-j*theta0);
            u_ctl = nco*U_Cons;
            
            I_est_1_2 = InterpLag(real(Reg_interp_1_2),u_ctl); 
            Q_est_1_2 = InterpLag(imag(Reg_interp_1_2),u_ctl);
            
            IntpZ(RevN) = I_est_1_2 + 1j*Q_est_1_2;
            RevN = RevN + 1 ;
            
            w_ctl_pre = w_ctl    ;
            cnt = cnt + 1;
        end
    else
        w_ctl_pre = w_ctl    ;
    end
    
    U_Cons = 1/w_ctl ;
    
    nco = mod(nco-w_ctl_pre,1);
end


RRCFilt  = rcosine(1,2,'fir/sqrt',0.35,9);
MFiltZ = conv(RRCFilt,IntpZ);  %匹配滤波


% figure;
% plot(real(MFiltZ(2:2:end)),'o');

scatterplot(MFiltZ(5000:2:end-500));

% scatterplot(IntpZ(5000:2:end-1000));
