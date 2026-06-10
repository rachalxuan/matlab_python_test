%% UQPSK调制程序

clear;
clc;
close all;
RRatio = 2	;	%I/Q速率比
ARatio = 2	;	%I/Q幅度比

Fs = 960	;	%采样率，单位MHz
Fd = 300   	;	%I支路传输速率，单位MBd，范围30至300
Fc = 240	;	%中频载波频率，单位MHz
%%
%产生I、Q传输信息序列
LenQ = 4096		;
LenI = LenQ*RRatio	;

InfoI = sign(randn(1,LenI))	;
InfoQ = sign(randn(1,LenQ))	;

InfoIs = InfoI;
InfoQs = zeros(1,LenI);

for k = 1:RRatio
	InfoQs(k:RRatio:end) = InfoQ	;
end

InfoZ = InfoIs + 1j*InfoQs/ARatio	;

%%
%基带成型滤波

RRCFilt  = rcosine(1,3,'fir/sqrt',0.35,9);
RRCFiltZ = conv(RRCFilt,upsample(InfoZ,3));


%%
%上采样 采样率变换，插值到960MHz
UpInterpR = 3/(Fs/Fd)	;
UIAccu  = 0	;
UIIndex = 2	;
k = 0;

while ( UIIndex < length(RRCFiltZ) - 2 )
	if ( UIAccu + UpInterpR < 1 )
		UIAccu = UIAccu + UpInterpR;
	else
		UIAccu  = UIAccu + UpInterpR - 1	;
		UIIndex = UIIndex + 1			;
	end
	
	InterpReg = RRCFiltZ( UIIndex+2 : -1 : UIIndex-1 )	;
	
	k = k + 1;
	IntpZ(k) = InterpLag(InterpReg,UIAccu)	;
end

%%
%I、Q数据调制到载波中频频率

ModSig = real(IntpZ.*exp(1j*2*pi*Fc/Fs*(1:length(IntpZ))));

pwelch(ModSig,[],[],[],Fs,'twosided');

%%
%保存为数据文件

savefile = 'ModSig.mat';
save(savefile, 'ModSig');


