function softSym = HelperCCSDSFACMDemodulate(sym,ACMFormat,nVar)
%HelperCCSDSFACMDemodulate Soft demodulate
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   SOFTSYM = HelperCCSDSFACMDemodulate(SYM,ACMFORMAT,NVAR) demodulates
%   the complex baseband symbols, SYM as specified by the adaptive coding
%   and modulation format, ACMFORMAT. ACMFORMAT is an integer value in the
%   range 1 to 27 [1]. NVAR is the noise variance and can be calculated
%   from the estimated signal to noise ratio (SNR). SOFTSYM is the soft
%   bits after demodulating the input complex symbols, SYM.
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.

%   Copyright 2021 The MathWorks, Inc.

m_Values = [2;2;2;2;2;2;3;3;3;3;3;3;4;4;4;4;4;5;5;5;5;5;6;6;6;6;6];
m = m_Values(ACMFormat);
radii = getRadiiValue(ACMFormat, m);

switch(m)
    case 2 % QPSK
        softSym = -1*qamdemod(sym,4,[2,3,0,1],'UnitAveragePower',true, ...
            'OutputType','approxllr','NoiseVariance',nVar);
    case 3 % 8PSK
        dm = comm.PSKDemodulator(8,pi/4,"BitOutput",true,"SymbolMapping","Custom", ...
            "CustomSymbolMapping",[0 1 3 2 6 7 5 4],"DecisionMethod","Approximate log-likelihood ratio", ...
            "VarianceSource","Input port");
        softSym = -1*dm(sym,nVar);
    case 4 % 16APSK
        mappatt = [3;7;15;11;2;0;1;5;4;6;14;12;13;9;8;10];
        softSym = -1*apskdemod(sym,[4,12],radii,[pi/4,pi/12],...
            'OutputType','approxllr','SymbolMapping',mappatt, ...
            'NoiseVariance',nVar);
    case 5
        mappatt = [17;21;29;25;1;0;16;20;4;5;13;12;28;24;8;9;3;2;19;18;...
            22;23;6;7;15;14;31;30;26;27;10;11];
        softSym = -1*apskdemod(sym,[4,12,16],radii,[pi/4,pi/12,0],...
            'OutputType','approxllr','SymbolMapping',mappatt, ...
            'NoiseVariance',nVar);
    otherwise % case 6
        mappatt = [8;40;56;24;10;11;9;41;43;42;58;59;57;25;27;26;2;3;7;...
            15;13;45;47;39;35;34;50;51;55;63;61;29;31;23;19;18;0;1;5;4;...
            6;14;12;44;46;38;36;37;33;32;48;49;53;52;54;62;60;28;30;22;...
            20;21;17;16];
        softSym = -1*apskdemod(sym,[4,12,20,28],radii,[pi/4,pi/12,pi/20,pi/28],...
            'OutputType','approxllr','SymbolMapping',mappatt, ...
            'NoiseVariance',nVar);
end
end

function r = getRadiiValue(ACMFormat, m)

switch(ACMFormat)
    case 13
        RadiiRatio = 3.15;
    case 14
        RadiiRatio = 3.15;
    case 15
        RadiiRatio = 2.85;
    case 16
        RadiiRatio = 2.75;
    case 17
        RadiiRatio = 2.60;
    case 18
        RadiiRatio = [2.84;5.27];
    case 19
        RadiiRatio = [2.84;5.27];
    case 20
        RadiiRatio = [2.84;5.27];
    case 21
        RadiiRatio = [2.72;4.87];
    case 22
        RadiiRatio = [2.54;4.33];
    otherwise % 64APSK modulation
        RadiiRatio = [2.73;4.52;6.31];
end
r = 1;
switch(m)
    case 4
        radius1 = sqrt(4/(1+3*(RadiiRatio(1)^2)));
        radius2 = RadiiRatio(1)*radius1; % This and the above equation are formed by solving for R1 and R2 from
        % RadiiRatio(1) = R2/R1 and from the unit energy constraint,
        % R1^2+3*R2^2 = 4.
        r = [radius1;radius2];
    case 5
        radius1 = sqrt(8/(1+3*(RadiiRatio(1)^2)+4*(RadiiRatio(2)^2)));
        radius2 = RadiiRatio(1)*radius1;
        radius3 = RadiiRatio(2)*radius1; % This and the above 2 equations are formed by solving for R1, R2 and R3 from
        % RadiiRatio(1) = R2/R1, RadiiRatio(2) = R3/R1
        % and from the unit energy constraint, R1^2 + 3*R2^2 + 4*R3^2 = 8.
        r = [radius1;radius2;radius3];
    case 6
        radius1 = sqrt(16/(1+3*(RadiiRatio(1)^2)+5*(RadiiRatio(2)^2)+7*(RadiiRatio(3)^2)));
        radius2 = RadiiRatio(1)*radius1;
        radius3 = RadiiRatio(2)*radius1;
        radius4 = RadiiRatio(3)*radius1; % This and the above 2 equations are formed by solving for R1, R2, R3 and R4 from
        % RadiiRatio(1) = R2/R1, RadiiRatio(2) = R3/R1, RadiiRatio(3) = R4/R1
        % and from the unit energy constraint, R1^2 + 3*R2^2 + 5*R3^2 + 7*R4^2 = 16.
        r = [radius1;radius2;radius3;radius4];
end
end

% LocalWords:  ACMFORMAT NVAR
