function sym = facmModulate(bits, m, radii)
%satcom.internal.ccsds.facmModulate Modulation scheme as specified in CCSDS
%131-2.B.1 standard
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   SYM = satcom.internal.ccsds.facmModulate(BITS, M, RADII)
%   maps the input bits, BITS to complex constellation value as specified
%   in [1] based on the modulation order, M. M is the modulation order
%   representing the number of bits that are mapped on to one constellation
%   symbol. RADII is the radius value of each circle in the APSK
%   constellation. This RADII property is not used in case of QPSK and 8PSK
%   modulation schemes.
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington,
%       D.C.: CCSDS, March 2012.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

switch(m)
    case 2 % QPSK
        symTemp = double(1 - 2*(reshape(bits, 2, length(bits)/2)));
        sym = (1/sqrt(2))*(symTemp(1,:)+ 1j*symTemp(2,:)).';
    case 3 % 8PSK
        modsym = [(1+1j)/sqrt(2);1j;-1;(-1+1j)/sqrt(2);1;(1-1j)/sqrt(2);(-1-1j)/sqrt(2);-1j];
        sym = modsym(comm.internal.utilities.bi2deLeftMSB(double(reshape(bits,3,length(bits)/3)'),2)+1);
    case 4 % 16APSK
        mappatt = [3;7;15;11;2;0;1;5;4;6;14;12;13;9;8;10];
        sym = apskmod(bits,[4,12],radii,[pi/4,pi/12],...
            'InputType','bit','SymbolMapping',mappatt);
    case 5 % 32APSK
        mappatt = [17;21;29;25;1;0;16;20;4;5;13;12;28;24;8;9;3;2;19;18;...
            22;23;6;7;15;14;31;30;26;27;10;11];
        sym = apskmod(bits,[4,12,16],radii,[pi/4,pi/12,0],...
            'InputType','bit','SymbolMapping',mappatt);
    otherwise % 64APSK
        mappatt = [8;40;56;24;10;11;9;41;43;42;58;59;57;25;27;26;2;3;7;...
            15;13;45;47;39;35;34;50;51;55;63;61;29;31;23;19;18;0;1;5;4;...
            6;14;12;44;46;38;36;37;33;32;48;49;53;52;54;62;60;28;30;22;...
            20;21;17;16];
        sym = apskmod(bits,[4,12,20,28],radii,[pi/4,pi/12,pi/20,pi/28],...
            'InputType','bit','SymbolMapping', mappatt);
end
end