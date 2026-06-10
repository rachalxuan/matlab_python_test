function encout = TPC_encoder(msg,n,k,G,genpoly) 
N = n+1; 
meth = 1; 
 
encout=zeros(N); 
 
switch meth  
    case 1 
        %-------------------------------------- 
        % Method one 
        %-------------------------------------- 
        encout(1:k,1:k)=msg; 
 
        % Row Encoder 
        encout(1:k,k+1:n) = mod(msg * G(:, 1:6), 2); 
 
        % Column Encoder 
        encout(k+1:n,1:n) = mod(encout(1:k,1:n)' * G(:, 1:6), 2)'; 
    case 2 
        %-------------------------------------- 
        % Method two 
        %-------------------------------------- 
        % Row Encoder 
        for i = 1:k 
            encout(i,1:n) = BCH_encoder(msg(i,:),G,genpoly,n,k); 
        end 
 
        % Column Encoder 
        for i = 1:n 
            encout(1:n,i) = BCH_encoder(encout(1:k,i)',G,genpoly,n,k); 
        end 
end 
 
% Row eHamming encode 
encout(:,N) = mod(sum(encout, 2), 2); 
 
% Col eHamming encode 
encout(N,:) = mod(sum(encout,1), 2);