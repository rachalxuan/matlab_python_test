function [field,A] = GenerateAntennaPattern_Gain(Satangles,theta,phi,data)
%
  anntexangles = [0,0,0]; % Mechanical rotation of the antenna,
  zeta = anntexangles(3);

  angles = [Satangles(1)+anntexangles(1),...
            Satangles(2)+anntexangles(2),...
            Satangles(3)];

  R = calculate_R(angles);
  [theta_p,phi_p,psi] = Angletransfor(theta,phi,R);

  A = antennagain(theta_p,phi_p,data,zeta);

  field = calculate_polarizedfield(A,zeta,psi);
end

function R = calculate_R(angles)
%TR 38.901 Equation 7.1-4
c = cosd(angles); % [cos(alpha) cos(beta) cos(gamma)]
ca = c(1); cb = c(2); cg = c(3);

s = sind(angles); % [sin(alpha) sin(beta) sin(gamma)]
sa = s(1); sb = s(2); sg = s(3);

R = zeros(3);
R(1,1) = ca*cb;
R(1,2) = ca*sb*sg - sa*cg;
R(1,3) = ca*sb*cg + sa*sg;
R(2,1) = sa*cb;
R(2,2) = sa*sb*sg + ca*cg;
R(2,3) = sa*sb*cg - ca*sg;
R(3,1) = -sb;
R(3,2) = cb*sg;
R(3,3) = cb*cg;

end

function [theta_p,phi_p,psi] = Angletransfor(theta,phi,R)
%TR 38.901 Section 7.1 Equation 7.1-6、7.1-7、7.1-8;

sinTheta = sind(theta);
cosTheta = cosd(theta);
sinPhi = sind(phi);
cosPhi = cosd(phi);

rho = [sinTheta.*cosPhi;
       sinTheta.*sinPhi;
              cosTheta];
R = R';
theta_p = real(acosd(R(3,:)*rho));
phi_p = atan2d(R(2,:)*rho, R(1,:)*rho);
% phi_p(theta_p==0) = 0; % Set ambiguous phi to 0 
% angles_ = [theta_p,phi_p];

cosThetaP = cosd(theta_p);
% theta vector in the LCS (TR 38.901 Equation 7.1-13)
theta_p_vec = [cosThetaP.*cosd(phi_p);
               cosThetaP.*sind(phi_p);
                      -sind(theta_p)];            

% theta and phi vectors in the GCS (TR 38.901 Equation 7.1-13 and -14)
phi_vec   = [-sinPhi; 
              cosPhi; 
            zeros(size(phi))];

theta_vec = [cosTheta.*cosPhi;
             cosTheta.*sinPhi;
                   -sinTheta];

% TR 38.901 Section 7.1 Equation 7.1-12

psi = atan2d(sum(phi_vec.*(R*theta_p_vec)),sum(theta_vec.*(R*theta_p_vec)));

end


% function  A = anntexgain(theta_p,phi_p)
% 
% direct_azimuth = 0;
% direct_zenith = 90;
% direct_out = xyz(direct_azimuth,direct_zenith);
% main_out = xyz(phi_p,theta_p);
% theta = acosd(sum(direct_out.*main_out));
% 
% ka = 10*2*pi;   %aperture radius of 10 wavelengths ,The aperture radius can be set to x wavelengths
% A = zeros(size(theta));
% thetaZero = (theta == 0);
% A(thetaZero) = 1;
% x = ka*sind(theta(~thetaZero));
% A(~thetaZero) = 4*abs(besselj(1,x)./x).^2;
% 
% % G_max = 0;
% % MaxGain = pow2db(0.65*ka*ka);  % dB
% MaxGain = 0.65*ka*ka;
% A = A.*MaxGain;
% end

function  A = antennagain(theta_p,phi_p,data,zeta)
%Antenna polarization direction,
if zeta ==0
    V_H_plane = 90;
else
    V_H_plane = 0;
end
% Determine whether the circular plan is LHCP or RHCP
isLHCP = true;   
isRhcp = ~isLHCP;

if theta_p == V_H_plane
    if isLHCP
        idxCol = 10;
    else
        idxCol = 11;
    end
else
    if isLHCP
        idxCol = 4;
    else
        idxCol = 5;
    end
end
numAntennaPattern = size(data,1);
gain = zeros(1,numAntennaPattern);
for i = 1:numAntennaPattern
    subdata = data{i};
    phi = subdata{:,3};
    idx = find(phi==phi_p,1);
    gain(i) = subdata{idx,idxCol};
end

A = sqrt(10.^(gain/10));
end

function field = calculate_polarizedfield(A,zeta,psi)
% Equation 7.1-11
jonesvector = 1/sqrt(2)*[1; -1j]; % jones vector right-hand circular polarization
                                  % left-hand circular polarization
                                  % jonesvector = 1/sqrt(2)*[1; j];
sinzeta = sind(zeta);
coszeta = cosd(zeta);
F = [(jonesvector(1)*coszeta+jonesvector(2)*sinzeta).*A;(jonesvector(2)*coszeta-jonesvector(1)*sinzeta).*A];
% F = reshape(F,2,1,size(F,2));
field = [F(1,:).*cosd(psi) - F(2,:).*sind(psi); F(1,:).*sind(psi) + F(2,:).*cosd(psi)];  % TR 38.901 Section 7.1 Equation 7.1-11
end


function out = xyz(phi,theta)

sintheta = sind(theta);
x = sintheta.*cosd(phi);
y = sintheta.*sind(phi);
z = cosd(theta);
out = [x; y; z];

end