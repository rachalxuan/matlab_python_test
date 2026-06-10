% TPC BER performance simulator. The extended hamming code is (64, 57) and 
% parity code is (64, 63). 
 
 
clc; 
clear all; 
close all; 
 
%-------------------------------------- 
% Sim Parameters 
%-------------------------------------- 
% coding parameters 
m = 6; 
n = 2^m-1; 
N = n+1; 
k = n-m; 
 
genpoly = [1 0 0 0 0 1 1];     
[H, G] = hammgen(m, genpoly); 
H = [H(:,m+1:end), H(:,1:m)]; 
 
% channel parameters 
Eb_N0 = 0:1:10; 
leng = length(Eb_N0); 
R = (k*k)/(N*N); 
sigma2 = 1./(2*R*10.^(Eb_N0/10)); % the variance of noise 
 
% decoding parameters 
iter_max = 6;                     
p = 4;                            
alpha = 0.5;                      
beta = 1;                         
 
% ber parameters 
n_cyc = 500;                     
BER_hd = zeros(1,leng);            
BER_sd = zeros(1,leng);           
 
for snridx=1:leng 
    disp(['???????Eb/N0=' num2str(Eb_N0(snridx))]); 
    for cyc = 1:n_cyc 
        %-------------------------------------- 
        % TPC Encoding 
        %-------------------------------------- 
        % k*k source message 
        msg = randi([0 1], k, k); 
        encout = TPC_encoder(msg,n,k,G,genpoly); 
 
        %-------------------------------------- 
        % BPSK modulation 0-> -1, 1 -> +1 
        %-------------------------------------- 
        tx_data = 2 * encout - 1; 
 
        %-------------------------------------- 
        % Add AWGN noise 
        %-------------------------------------- 
        rx_data = tx_data + sqrt(sigma2(snridx))*randn(N, N); 
         
        %-------------------------------------- 
        % TPC decoding 
        %-------------------------------------- 
        [decout, ~] = TPC_decoder(rx_data, n, k, H, p, alpha, beta, iter_max); 
         
        %-------------------------------------- 
        % BER performance 
        %-------------------------------------- 
        % hard decision 
        hd_data = double(rx_data >= 0); 
        BER_hd = BER_hd + sum(sum(abs(msg-hd_data(1:k,1:k)))); 
        BER_sd = BER_sd + sum(sum(abs(msg-decout))); 
    end 
end 
BER_hd=BER_hd/(n_cyc*k*k); 
BER_sd=BER_sd/(n_cyc*k*k); 
 
semilogy(Eb_N0,BER_hd,'b-',Eb_N0,BER_sd,'r-'); 
xlabel('E_b/N_0(dB)'); 
ylabel('BER'); 
title('TPC??BER????????')