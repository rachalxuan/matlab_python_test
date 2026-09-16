function test_ldpc_boundary_soft_metrics
% Deterministic interface regression, not a fading-channel performance test.
addpath(fileparts(fileparts(mfilename('fullpath'))));
oldRng=rng; cleanup=onCleanup(@()rng(oldRng));
rng(364232726,'twister');

% An upstream-verified boundary must survive eight corrupted startup ASMs.
% Codewords are intact: bad ASM telemetry must not drop or shift them.
g=ccsdsTMWaveformGenerator('Modulation','8PSK','ChannelCoding','LDPC', ...
    'NumBitsInInformationBlock',1024,'CodeRate','1/2', ...
    'IsLDPCOnSMTF',false,'HasASM',true,'RandomizerEnabled',false);
u=int8(randi([0 1],12*1024,1));
[~,encoded]=g(u);
assert(numel(encoded)==12*2112);
soft=reshape(20*(2*double(encoded)-1),2112,[]);
soft(1:64,1:8)=-soft(1:64,1:8);
soft=soft(:);
args={'Modulation','8PSK','ChannelCoding','LDPC', ...
    'NumBitsInInformationBlock',1024,'CodeRate','1/2', ...
    'IsLDPCOnSMTF',false,'HasASM',true,'RandomizerEnabled',false, ...
    'DisableFrameSynchronization',true,'DisablePhaseAmbiguityResolution',true};
d=HelperCCSDSTMDecoder(args{:});
decoded=d(soft(:)); positions=d.getDecodedFramePositions();
telemetry=d.getFrameSyncTelemetry();
assert(isequal(int8(decoded(:)),u),'Verified boundary or LLR polarity changed.');
assert(isequal(positions.InputStartBit,(1:2112:numel(encoded)).'));
assert(strcmp(telemetry.Source,'upstream-aligned-raw-asm'));
assert(all(~telemetry.ASMObservationAccepted(1:8)) && ...
    all(telemetry.ASMObservationAccepted(9:12)));
assert(all(~telemetry.Locked(1:8)) && telemetry.LockedAtEnd);
% The same contract must hold across an incomplete input call.
d=HelperCCSDSTMDecoder(args{:});
d(soft(1:97));
decoded=d(soft(98:end)); positions=d.getDecodedFramePositions();
assert(isequal(int8(decoded(:)),u));
assert(isequal(positions.InputStartBit,(1:2112:numel(encoded)).'));
fprintf('PASS: startup ASM corruption cannot shift, invert or exclude aligned LDPC frames.\n');

for modName=["BPSK","QPSK","8PSK"]
    if modName=="BPSK"
        m=2; phase=0; mapping=[0 1];
    elseif modName=="QPSK"
        m=4; phase=pi/4; mapping=[0 2 3 1];
    else
        m=8; phase=pi/8; mapping=[0 4 6 2 3 7 5 1];
    end
    modulator=comm.PSKModulator(m,phase,'SymbolMapping','Custom', ...
        'CustomSymbolMapping',mapping);
    c=modulator((0:m-1).');
    z=c.*(1+0.08+0.06j);
    v=HelperTMPSKResidualVariance(z,c);
    assert(abs(v-0.01)<1e-12,'Residual variance must retain demapper amplitude units.');
    assert(abs(HelperTMPSKResidualVariance(z*exp(2j*pi/m),c)-v)<1e-12);
    assert(HelperTMPSKResidualVariance(c,c)==1e-4);

    for coding=["LDPC","turbo"]
        demod1=HelperCCSDSTMDemodulator('Modulation',char(modName), ...
            'ChannelCoding',char(coding),'NoiseVariance',1);
        demod4=HelperCCSDSTMDemodulator('Modulation',char(modName), ...
            'ChannelCoding',char(coding),'NoiseVariance',0.25);
        a=demod1(z); b=demod4(z);
        assert(max(abs(b-4*a))<1e-10 && isequal(a>0,b>0));
        if modName=="BPSK", assert(max(abs(a-4*real(z)))<1e-12); end
        demodClean=HelperCCSDSTMDemodulator('Modulation',char(modName), ...
            'ChannelCoding',char(coding),'NoiseVariance',1e-4);
        llr=demodClean(c);
        assert(all(isfinite(llr)) && max(abs(llr))<=50);
    end

    % Protect the native pre-existing metrics of OTHER coding routes.
    native=comm.PSKDemodulator(m,phase,'BitOutput',true, ...
        'DecisionMethod','Approximate log-likelihood ratio','Variance',1, ...
        'SymbolMapping','Custom','CustomSymbolMapping',mapping);
    if modName=="BPSK", expected=real(z); else, expected=-native(z); end
    for coding=["none","convolutional","RS","TPC"]
        unchanged=HelperCCSDSTMDemodulator('Modulation',char(modName), ...
            'ChannelCoding',char(coding));
        actual=unchanged(z);
        assert(isequal(actual,expected),'Legacy hard/Viterbi/Chase metric changed.');
    end
    fprintf('PASS: %s LDPC/Turbo variance/sign/clipping; other coding metrics unchanged.\n',modName);
end
end
