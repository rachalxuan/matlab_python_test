function test_iterative_psk_soft_inputs
% Encoder -> known PSK mapper -> calibrated demapper -> real FEC decoder.
% No channel/time/carrier changes. Protect rate, polarity and randomization.
addpath(fileparts(fileparts(mfilename('fullpath'))));
oldRng=rng; cleanup=onCleanup(@()rng(oldRng));
rng(7403,'twister');
codes={'LDPC','turbo','turbo','turbo','turbo'};
rates={'1/2','1/2','1/3','1/4','1/6'};
lengths=[1024 3568 3568 3568 3568];
for modName=["BPSK","QPSK","8PSK"]
    for k=1:numel(codes)
        for randomized=[false true]
            args={'Modulation',char(modName),'ChannelCoding',codes{k}, ...
                'CodeRate',rates{k},'NumBitsInInformationBlock',lengths(k), ...
                'HasASM',true,'RandomizerEnabled',randomized};
            if strcmp(codes{k},'LDPC'), args=[args,{'IsLDPCOnSMTF',false}]; end
            g=ccsdsTMWaveformGenerator(args{:});
            u=int8(randi([0 1],3*g.NumInputBits,1));
            [~,encoded]=g(u);
            if modName=="BPSK"
                z=2*double(encoded)-1;
            else
                if modName=="QPSK"
                    m=4; phase=pi/4; mapping=[0 2 3 1];
                else
                    m=8; phase=pi/8; mapping=[0 4 6 2 3 7 5 1];
                end
                mapper=comm.PSKModulator(m,phase,'BitInput',true, ...
                    'SymbolMapping','Custom','CustomSymbolMapping',mapping);
                z=mapper(double(encoded));
            end
            demod=HelperCCSDSTMDemodulator('Modulation',char(modName), ...
                'ChannelCoding',codes{k},'NoiseVariance',0.05);
            soft=demod(z);
            assert(all((soft>0)==logical(encoded)),'PSK sign/bit order mismatch.');
            decoder=HelperCCSDSTMDecoder(args{:},'DisableFrameSynchronization',true, ...
                'DisablePhaseAmbiguityResolution',true);
            decoded=decoder(soft);
            assert(isequal(int8(decoded(:)),u),'Clean calibrated FEC interface failed.');
        end
        fprintf('PASS: %s %s %s, randomizer OFF/ON, 3 frames each.\n',modName,codes{k},rates{k});
    end
end
end
