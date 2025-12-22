function [bits,txOut,rxIn,phyParams,rxParams] = HelperCCSDSFACMRxInputGenerate(cfg,simParams)
%HelperCCSDSFACMRxInputGenerate Generate receiver input (Fixed Version)

NumPLFrames = simParams.NumPLFrames;
sps = cfg.SamplesPerSymbol;

% Initialize the CCSDS FACM waveform generator system object
facmWaveGen = ccsdsTMWaveformGenerator("WaveformSource","flexible advanced coding and modulation");
set(facmWaveGen, cfg);

rng default
% Generate tx input bits
numCodeBlks = 16;
numTF = NumPLFrames*facmWaveGen.MinNumTransferFrames*numCodeBlks;
bits = logical(randi([0,1],facmWaveGen.NumInputBits,numTF));

% Generate the transmitter output
txOut = facmWaveGen(bits(:));

% Initialize the phy-parameters
phyParams = info(facmWaveGen);
phyParams = rmfield(phyParams,"SubcarrierFrequency");
phyParams.NumInputBits = facmWaveGen.NumInputBits;
phyParams.ASM = 2*[0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;...
                        0;1;1;1;0;1] - 1; 
K_Values = [5758;6958;8398;9838;11278;13198;11278;13198;14878;17038;...
            19198;21358;19198;21358;23518;25918;28318;25918;28318;30958;33358;...
            35998;33358;35998;38638;41038;43678];
phyParams.K = K_Values(facmWaveGen.ACMFormat);

Rsymb = simParams.SymbolRate;
Fsamp = Rsymb*simParams.SPS;

if simParams.DisableRFImpairments == false
    if simParams.DisableCFO == false
        pfo = comm.PhaseFrequencyOffset('FrequencyOffset',simParams.CFO,'SampleRate',Fsamp);
        cfoOut = pfo(txOut);
    else
        cfoOut = txOut;
    end

    signalAttenuated = simParams.AttenuationFactor*cfoOut;

    if simParams.DisableDoppler == false
        dopp = HelperDopplerShift('DopplerRate',simParams.DopplerRate, ...
            'PeakDoppler',simParams.PeakDoppler, 'SampleRate',Fsamp);
        doppOut = dopp(signalAttenuated);
    else
        doppOut = signalAttenuated;
    end

    if simParams.DisablePhaseNoise == false
        freqOffset = [1e3,5e3,2e5,3e6,1e7];
        powerLevel = [-100,-105,-110,-120,-120];
        hpNo = comm.PhaseNoise('Level',powerLevel,'FrequencyOffset',freqOffset,'SampleRate',Fsamp);
        warning('OFF','shared_comm_msblks_serdes:phnoiseblk:SpecNotMet')
        phNOut = hpNo(doppOut);
        warning('ON','shared_comm_msblks_serdes:phnoiseblk:SpecNotMet')
    else
        phNOut = doppOut;
    end

    if simParams.DisableSRO == false
        sro = comm.SampleRateOffset(simParams.SRO);
        sroOut = sro(phNOut);
    else
        sroOut = phNOut;
    end
else
    sroOut = txOut;
end

rxIn = awgn(sroOut(:), simParams.EsNodB - 10*log10(sps), 'measured');

% Receiver parameters generation
numBlks = 15;
numPilotsPerBlk = 16;
n = 8100 + numPilotsPerBlk*numBlks*facmWaveGen.HasPilots; 
qpskmap = [1;1j;-1;-1j];
derandseq = satcom.internal.ccsds.facmPLScramblingSequence(facmWaveGen.ScramblingCodeNumber,n*numCodeBlks);
rxParams.PLRandomSymbols = reshape(qpskmap(derandseq+1),n,numCodeBlks); 

ind = (1:numPilotsPerBlk)'; 
nB = 1:numBlks;
offset = 540*nB+(nB-1)*numPilotsPerBlk; 
temp = ind+offset; 
rxParams.PilotIndices = temp(:);

temp1 = repmat(rxParams.PilotIndices,1,numCodeBlks);
offset1 = 0:n:(numCodeBlks-1)*n;
allPilotIndices = temp1+offset1;
rxParams.PilotIndices = allPilotIndices(:);

if facmWaveGen.HasPilots
    rxParams.PilotSeq = (1+1j)*rxParams.PLRandomSymbols(rxParams.PilotIndices);
    % --- 关键修复：仅当开启导频时才执行删除操作 ---
    rxParams.PLRandomSymbols(rxParams.PilotIndices) = [];
end

rxParams.plFrameSize = n*16 + 320; 
rxParams.RefFM = HelperCCSDSFACMFrameMarker();
end