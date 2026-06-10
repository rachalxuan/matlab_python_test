function y = InterpLag(X,u)
%INTERP_LANGRANG Summary of this function goes here
%   Detailed explanation goes here
c1 = [0 0 1 0];
c2 = [-1/6 1 -1/2 -1/3];
c3 = [0 1/2 -1 1/2];
c4 = [1/6 -1/2 1/2 -1/6];
C = [c1;c2;c3;c4];

Y = C*X.';
y = [1 u u^2 u^3]*Y;
