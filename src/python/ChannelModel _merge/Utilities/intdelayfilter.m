
load CDLModel.mat

samples = 1e7;
signal_in = rand(1,1e7);
signallength = size(signal_in,2);
ndelay = tao_n*samples;
npath = size(tao_n,1);
intdelay = round(ndelay);
signal = zeros(npath,signallength);
for i = 1:npath
    if intdelay(i) ~= 0
        signal(i,:) = [zeros(1,intdelay(i))  signal_in(1:signallength-intdelay(i))];
    else
        signal(i,:) = signal_in;
    end
end
signal_out = H_Martix_t.* signal;
signal_out = signal_out';





