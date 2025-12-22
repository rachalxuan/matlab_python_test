function refConstellation = HelperCCSDSFACMReferenceConstellation(ACMFormat)
%HelperCCSDSFACMReferenceConstellation Reference constellation
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   REFCONSTELLATION = HelperCCSDSFACMReferenceConstellation(ACMFORMAT)
%   generates the reference constellation for the specified adaptive coding
%   and modulation (ACM) format, ACMFORMAT that is specified in [1]. 
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.

%   Copyright 2021 The MathWorks, Inc.

m_Values = [2;2;2;2;2;2;3;3;3;3;3;3;4;4;4;4;4;5;5;5;5;5;6;6;6;6;6];
m = m_Values(ACMFormat);
r = getRadiiValue(ACMFormat, m);
bits = int2bit(0:2^m-1,m);
refConstellation = satcom.internal.ccsds.facmModulate(bits(:),m,r);
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

% LocalWords:  REFCONSTELLATION ACMFORMAT
