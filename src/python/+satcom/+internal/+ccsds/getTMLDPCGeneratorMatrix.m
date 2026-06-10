function g = getTMLDPCGeneratorMatrix(k, invr)
%satcom.internal.ccsds.getTMLDPCGeneratorMatrix Generator matrix for the
%LDPC codes of CCSDS TM Synchronization and channel coding standard
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   G = satcom.internal.ccsds.getTMLDPCGeneratorMatrix(K,INVR) gets the
%   generator matrix, G that is needed for the LDPC codes specified
%   in CCSDS 131-0.B-3 TM synchronization and channel coding standard [1].
%   K is the number of bits in one information block. INVR is the numeric
%   value of the inverse of the code rate. E.g., if code rate is 1/2, then
%   INVR = 2.
%
%   References: 
%
%   [1] TM Synchronization and Channel Coding. Recommendation
%       for Space Data System Standards, CCSDS 131.0-B-3. Blue Book. Issue
%       3. Washington, D.C.: CCSDS, September 2017.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

if  k == 1024
    if invr == 2
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG1024Rate1By2');
        g = G.LDPCG1024Rate1By2;
    elseif invr == 1.5
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG1024Rate2By3');
        g = G.LDPCG1024Rate2By3;
    else % invr == 1.25
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG1024Rate4By5');
        g = G.LDPCG1024Rate4By5;
    end
elseif k == 4096
    if invr == 2
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG4096Rate1By2');
        g = G.LDPCG4096Rate1By2;
    elseif invr == 1.5
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG4096Rate2By3');
        g = G.LDPCG4096Rate2By3;
    else % invr == 1.25
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG4096Rate4By5');
        g = G.LDPCG4096Rate4By5;
    end
elseif k == 16384
    if invr == 2
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG16384Rate1By2');
        g = G.LDPCG16384Rate1By2;
    elseif invr == 1.5
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG16384Rate2By3');
        g = G.LDPCG16384Rate2By3;
    else % invr == 1.25
        G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG16384Rate4By5');
        g = G.LDPCG16384Rate4By5;
    end
else % k == 7136
    G = coder.load('+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat','LDPCG7136Rate7By8');
    g = G.LDPCG7136Rate7By8;
end
end