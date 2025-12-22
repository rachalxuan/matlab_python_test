function decoded = HelperSCCCDecode(softBits,ACMFormat,numIterations)
%HelperSCCCDecode Iterative decoder of SCCC
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   DECODED = HelperSCCCDecode(SOFTBITS,ACMFORMAT,NUMITERATIONS) decode the
%   serial concatenated convolutional code (SCCC) codeword, SOFTBITS.
%   ACMFORMAT specifies the adaptive coding and modulation (ACM) format
%   that is specified in [1]. NUMITERATIONS specifies the number of
%   decoding iterations.
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.

%   Copyright 2021 The MathWorks, Inc.

m_Values = [2;2;2;2;2;2;3;3;3;3;3;3;4;4;4;4;4;5;5;5;5;5;6;6;6;6;6];
m = m_Values(ACMFormat);

% Row column deinterleaving
bitMat = reshape(softBits,m,8100); % 8100 symbols
softBits = reshape(bitMat.',[],1);

[depunctured,interleavingIndices] = scccDepuncture2(softBits,ACMFormat);
I = length(interleavingIndices);
Id = 4*I/3;
depuncture1 = true(Id,1);
depuncture1(4:4:end) = false;

% Turbo kind of decoding
SCCCTrellisStructure = poly2trellis(3,[7,5],7);
innerAPPDec = comm.APPDecoder(SCCCTrellisStructure,"TerminationMethod","Terminated", ...
    "CodedBitLLROutputPort",false); % For SCCC decoding, second output port of 1st APP decoder is not needed
outerAPPDec = comm.APPDecoder(SCCCTrellisStructure,"TerminationMethod","Terminated");
lci = reshape(reshape(depunctured,[],2).',[],1);
lui = zeros(length(depunctured)/2,1);
luo = zeros(Id/2,1);
for iIter = 1:numIterations
    % First APP decoder
    luie = innerAPPDec(lui,lci);

    % Deinterleaver
    temp = zeros(length(luie)-2,1); % 2 Tail bits
    temp(interleavingIndices) = luie(1:end-2);

    % Depuncture before giving to second APP decoder
    lco = zeros(Id,1);
    lco(depuncture1) = temp;

    % Pass through APP decoder
    [luoe,lcoe] = outerAPPDec(luo,lco);

    % Puncture the output of 2nd APP decoder before giving to interleaver
    lcoe = lcoe(depuncture1);

    % Interleave before iterating
    lui = zeros(I+2,1); % To account for 2 tail bits
    lui(1:end-2) = lcoe(interleavingIndices);
end
decoded = luoe(1:end-2);
end

function [depunctured,interleavingIndices] = scccDepuncture2(softBits,ACMFormat)

K_Values = [5758;6958;8398;9838;11278;13198;11278;13198;14878;17038;...
            19198;21358;19198;21358;23518;25918;28318;25918;28318;30958;33358;...
            35998;33358;35998;38638;41038;43678];
k = K_Values(ACMFormat);
interleavingIndices = getSCCCInterleavingIndices(k);
systematicPunturePattern = [getSCCCPuncturePattern2(ACMFormat,interleavingIndices);true;true]; % To account for the terminating bits from the systematic side
[~,parityPassingIndices] = scccParityPunture2Indices(ACMFormat);
numParityBits = length(interleavingIndices); % To account for the terminating bits from the parity side
% numSystematicBits = length(softBits)-numParityBits;
systematicBits = zeros(size(systematicPunturePattern));

systematicBits(systematicPunturePattern) = softBits(1:nnz(systematicPunturePattern));
parityBits = zeros(numParityBits,1);
parityBits(parityPassingIndices) = softBits(nnz(systematicPunturePattern)+1:end-2);
depunctured = [systematicBits(:);parityBits(:);softBits(end-1:end)];
end

function InterleavingIndices = getSCCCInterleavingIndices(k)
IVal = 3*(k+2)/2;
SCCCInterleaverParameters = satcom.internal.ccsds.scccInterleaverParameters(IVal);
alpha = SCCCInterleaverParameters(:,1);
beta = SCCCInterleaverParameters(:,2);
piVal = zeros(IVal,1);
WVal = IVal/120;
for idx = 0:IVal-1
    piVal(idx+1,1) = WVal*(mod(floor(idx/WVal)+beta(mod(idx,WVal)+1),120)) + alpha(mod(idx,WVal)+1) + 1;
end
InterleavingIndices = piVal;
end

function SCCCPuncturePattern2 = getSCCCPuncturePattern2(ACMFormat, InterleavingIndices)
% Calculate puncture positions
Ssur_Values = [300;300;274;251;234;218;292;240;250;234;221;214;255;241;...
    230;220;211;245;234;224;217;210;236;228;220;214;208];
PuncturePosition_Values = [76;1;145;214;256;37;109;181;277;235;...
    55;127;163;19;199;91;289;244;64;268;223;136;172;28;100;190;10;...
    46;118;154;81;207;259;292;232;67;280;247;147;30;111;183;6;48;...
    93;165;129;219;195;270;72;15;297;211;138;102;174;39;250;57;...
    120;156;84;229;193;283;262;25;238;60;201;294;132;96;159;34;...
    265;114;177;225;79;12;151;51;274;204;105;4;241;169;69;124;22;...
    216;285;141;252;187;206;36];
Ssur = Ssur_Values(ACMFormat);
AvailableSsur = 299:-1:200;
idx = find(AvailableSsur==Ssur, 1);
if ~isempty(idx)
    PuncturePositions = PuncturePosition_Values(1:idx(1));
else
    PuncturePositions = zeros(0,1);
end

pattern = true(300,1);
pattern(PuncturePositions+1,1) = false;
jVal = mod(InterleavingIndices-1,300)+1;
SCCCPuncturePattern2 = pattern(jVal);
end

function [DeltaIndices, PassingIndices] = scccParityPunture2Indices(ACMFormat)

Delta_Values = [1084;4684;7912;10913;13922;17992;9092;11344;...
    16624;21201;25720;30599;20884;25383;29933;34997;39962;30137;...
    35119;40619;45739;51304;40808;46444;51869;56877;62351];
K_Values = [5758;6958;8398;9838;11278;13198;11278;13198;14878;17038;...
            19198;21358;19198;21358;23518;25918;28318;25918;28318;30958;33358;...
            35998;33358;35998;38638;41038;43678];
k = K_Values(ACMFormat);
I = 3*(k+2)/2;
Delta = Delta_Values(ACMFormat);
e = 1;
cnt = 1;
cnt1 = 1;
PassingIndices = zeros(I-Delta,1);
DeltaIndices = zeros(Delta,1);
for idx = 1:I
    if e>0
        % p1p(cnt) = c1p(idx);
        PassingIndices(cnt) = idx;
        cnt = cnt + 1;
    else
        DeltaIndices(cnt1) = idx;
        cnt1 = cnt1 + 1;
        e = e + I;
    end
    e = e - Delta;
end
end

% LocalWords:  SOFTBITS ACMFORMAT NUMITERATIONS deinterleaving Depuncture nd cnt
