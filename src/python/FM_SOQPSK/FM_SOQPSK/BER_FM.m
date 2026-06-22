% function  BER_FM

clc
close all;
clear all

%% 参数
fd=20e6;
fs=fd*4;
fdoppler=2e6;
show_figure=0;
N_per_frame=10000;
N_frame=10;
r_cos_factor=0.5;
interN=fs/fd;
interN_db=10*log10(interN);
TZZS=[0.715];%调制指数
SNR=6:10;
L=length(SNR);
m=1;
ss=1;
figure;
kk=1;jj=1;ii=1;
h=figure;
while kk<=length(TZZS)
    kk
    jj=1;
    while jj<=L
        N_errorbit=FM_demodulation(fd,fs,fdoppler,N_per_frame,N_frame,r_cos_factor,TZZS(kk),SNR(jj),show_figure);
        BER(kk,jj)=N_errorbit/(N_per_frame*N_frame)
        jj=jj+1;
    end
    switch mod(ss,6)
        case 1
            p_str ='-sb';
        case 2
            p_str ='-or';
        case 3
            p_str ='-xm';
        case 4 
            p_str ='-vg';
        case 5
            p_str ='-+k';
        case 6
            p_str ='-*y';
        case 6
            p_str ='-^y';
    end
    semilogy(SNR+interN_db,BER(kk,:),p_str);
    hold on;ss=ss+1;

    kk=kk+1;
end
save data\BER BER
grid on;
