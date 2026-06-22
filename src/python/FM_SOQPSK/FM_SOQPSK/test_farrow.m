clc
close all
clear all
delt_t=pi/2;
t=0:delt_t:10*pi;
y=sin(t);
figure;plot(t,y);


tt=pi/4*5+0.8:delt_t/10:8*pi;
for ii=1:length(tt)
    integral=floor((tt(ii)-t(1))/delt_t)+1;%整数
    fraction=mod((tt(ii)-t(1)),delt_t)/delt_t;%分数

    F1=0.5*y(integral+2)-0.5*y(integral+1)-0.5*y(integral)+0.5*y(integral-1);
    F2=1.5*y(integral+1)-0.5*y(integral+2)-0.5*y(integral)-0.5*y(integral-1);
    F3=y(integral);
    data_intet(ii)=(F1*fraction+F2)*fraction+F3;%内插值
    data_theory(ii)=sin(tt(ii));%理论值
    data_error(ii)=data_intet(ii)-data_theory(ii);
end
figure;
plot(t,y,'-vk');hold on;grid on;
plot(tt,data_intet,'-or');
hold on;plot(tt,data_theory,'-*b');
legend('内插值','理论值');
figure;plot(data_error);
