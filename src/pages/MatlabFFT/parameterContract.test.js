import {
  finalizeTMRequest,
  codingDefaults,
  constellationExplanation,
  FULL_RS_INTERLEAVING_DEPTHS,
  modulationBitsPerSymbol,
  resolveModulationRates,
  RS_PRESETS,
} from './parameterContract';
const base = { modType: 'QPSK', channelCoding: 'none', sps: 8, hasASM: true, DataPathMode: 'single', NumBytesInTransferFrame: 1151, symbolRate: 10e6 };
test.each([
  ['QPSK', 2, 300],
  ['OQPSK', 2, 300],
  ['UQPSK', 1.5, 400],
  ['8PSK', 3, 200],
  ['16QAM', 4, 150],
  ['32QAM', 5, 120],
])('%s converts a device-style 600 Mbps modulation rate to symbol rate', (modType, bitsPerSymbol, expectedMsym) => {
  const p = finalizeTMRequest({...base, modType, modulatorBitRateMbps: 600});
  expect(modulationBitsPerSymbol(modType)).toBe(bitsPerSymbol);
  expect(p.NominalBitsPerSymbol).toBe(bitsPerSymbol);
  expect(p.ModulatorBitRate_bps).toBe(600e6);
  expect(p.symbolRate).toBe(expectedMsym * 1e6);
  expect(p.RateInputMode).toBe('modulator-bit-rate');
});
test('legacy symbolRate callers remain supported and obtain the equivalent modulation rate', () => {
  const p = resolveModulationRates({modType:'16QAM', symbolRate:150e6});
  expect(p.modulatorBitRateMbps).toBe(600);
  expect(p.ModulatorBitRate_bps).toBe(600e6);
  expect(p.RateInputMode).toBe('symbol-rate');
});
test.each(['16APSK','32APSK'])('%s uses pilotless ordinary TM, no FACM leftovers', modType => {
  const p = finalizeTMRequest({...base, modType});
  expect(p).toMatchObject({WaveformMode:'ordinaryTM', HasTMAPSKPilots:false, APSKReceiverMode:'pilotless'});
  expect(p.enableFACMEqualizer).toBeUndefined();
});
test.each([
  {WaveformMode:'FACM'}, {ACMFormat:21}, {hasPilots:true},
  {HasTMAPSKPilots:true}, {HasTMAPSKPilots:false,hasTMAPSKPilots:true},
  {APSKReceiverMode:'legacy'}, {APSKReceiverMode:'pilotless',apskReceiverMode:'pilot-aided'},
  {useFACM:true}, {useTMAPSKPilots:true}, {enableFACMEqualizer:true},
])('APSK rejects retired requests without overwriting them: %j', request => {
  expect(() => finalizeTMRequest({...base,modType:'16APSK',...request})).toThrow();
});
test('all verified full-length RS profiles are exposed with the correct TF size', () => {
  expect(Object.keys(RS_PRESETS)).toHaveLength(12);
  for (const k of [223, 239]) {
    for (const i of FULL_RS_INTERLEAVING_DEPTHS) {
      expect(RS_PRESETS[`rs-255-${k}-i${i}`]).toMatchObject({
        RSMessageLength: k,
        RSInterleavingDepth: i,
        IsRSMessageShortened: false,
        NumBytesInTransferFrame: k * i,
      });
    }
  }
});
test('ordinary single-path RS/rate profiles route to the common receiver (parameter contract only)', () => {
  for (const modType of ['BPSK', 'QPSK', '8PSK', '16QAM', '32QAM', '16APSK', '32APSK', 'OQPSK', 'UQPSK']) {
    for (const k of [223, 239]) {
      for (const i of FULL_RS_INTERLEAVING_DEPTHS) {
        for (const rate of ['1/2', '2/3', '3/4', '5/6', '7/8']) {
          const p = finalizeTMRequest({
            ...base,
            modType,
            channelCoding: 'concatenated',
            ConvolutionalCodeRate: rate,
            RSMessageLength: k,
            RSInterleavingDepth: i,
            IsRSMessageShortened: false,
            RandomizerEnabled: false,
            PCMFormat: 'NRZ-L',
          });
          expect(p.ConvolutionalReceiveMode).toBe('stream-raw-asm');
          expect(p.NumBytesInTransferFrame).toBe(k * i);
          expect(p.RSShortenedMessageLength).toBeUndefined();
        }
      }
    }
  }
});
test('unsupported RS profiles and unaligned legacy fallbacks are rejected instead of silently changed', () => {
  const p = {...base, channelCoding:'concatenated', RSMessageLength:223, RSInterleavingDepth:5, NumBytesInTransferFrame:1115};
  expect(() => finalizeTMRequest({...p, IsRSMessageShortened:true, RSShortenedMessageLength:200, ConvolutionalCodeRate:'1/2'})).toThrow('缩短 RS');
  expect(() => finalizeTMRequest({...p, RSInterleavingDepth:6, ConvolutionalCodeRate:'1/2'})).toThrow('1、2、3、4、5、8');
  expect(() => finalizeTMRequest({...p, RandomizerEnabled:true, ConvolutionalCodeRate:'5/6'})).toThrow('旧 coded-ASM');
});

test.each(['16APSK', '32APSK'])('%s connects RRC/none soft bits to the common continuous convolutional route', modType => {
  for (const PulseShapingFilter of ['root raised cosine', 'none']) {
    for (const ConvolutionalCodeRate of ['1/2', '2/3', '3/4', '5/6', '7/8']) {
      for (const channelCoding of ['convolutional', 'concatenated']) {
        const p = finalizeTMRequest({
          ...base, modType, PulseShapingFilter, channelCoding, ConvolutionalCodeRate,
          NumBytesInTransferFrame: 258, RSMessageLength: 223, RSInterleavingDepth: 1,
          PCMFormat: 'NRZ-L', RandomizerEnabled: false,
        });
        expect(p).toMatchObject({
          WaveformMode: 'ordinaryTM', APSKReceiverMode: 'pilotless', HasTMAPSKPilots: false,
          ConvolutionalReceiveMode: 'stream-raw-asm', ConvolutionalCodeRate, PulseShapingFilter,
        });
        expect(p.NumBytesInTransferFrame).toBe(channelCoding === 'concatenated' ? 223 : 258);
      }
    }
  }
  // Randomization has not been integrated into this continuous stream route.
  expect(() => finalizeTMRequest({
    ...base, modType, channelCoding: 'convolutional', ConvolutionalCodeRate: '5/6',
    NumBytesInTransferFrame: 258, RandomizerEnabled: true,
  })).toThrow('旧 coded-ASM');
});
test('coding switches clear stale K and select compatible concatenation', () => {
  expect(codingDefaults('Turbo').NumBitsInInformationBlock).toBe(3568);
  expect(codingDefaults('LDPC').NumBitsInInformationBlock).toBe(1024);
  expect(codingDefaults('concatenated').ConvolutionalCodeRate).toBe('1/2');
  expect(() => finalizeTMRequest({...base, channelCoding:'Turbo',NumBitsInInformationBlock:1024})).toThrow('Turbo');
});

test.each(['OQPSK', 'UQPSK'])('%s routes only eligible combined convolutional requests to stream mode', modType => {
  for (const PulseShapingFilter of ['root raised cosine', 'none']) {
    for (const ConvolutionalCodeRate of ['1/2', '2/3', '3/4', '5/6', '7/8']) {
      for (const channelCoding of ['convolutional', 'concatenated']) {
        const p = finalizeTMRequest({
          ...base, modType, PulseShapingFilter, channelCoding, ConvolutionalCodeRate,
          NumBytesInTransferFrame: 258, RSMessageLength: 223, RSInterleavingDepth: 1,
          PCMFormat: 'NRZ-L', RandomizerEnabled: false,
        });
        expect(p).toMatchObject({
          modType, PulseShapingFilter, channelCoding, ConvolutionalCodeRate,
          ConvolutionalReceiveMode: 'stream-raw-asm', DataPathMode: 'single',
        });
      }
    }
  }
  const request = {...base, modType, channelCoding: 'convolutional',
    ConvolutionalCodeRate: '5/6', NumBytesInTransferFrame: 258, PCMFormat: 'NRZ-L'};
  expect(() => finalizeTMRequest({...request, RandomizerEnabled: true})).toThrow('旧 coded-ASM');
  expect(() => finalizeTMRequest({...request, PCMFormat: 'NRZ-M'})).toThrow('旧 coded-ASM');
  expect(finalizeTMRequest({...request, ConvolutionalCodeRate: '1/2', hasASM: false})
    .ConvolutionalReceiveMode).toBe('legacy-coded-asm');
  const split = finalizeTMRequest({...request, ConvolutionalCodeRate: '1/2',
    PulseShapingFilter: 'root raised cosine', DataPathMode: modType === 'UQPSK' ? 'unequalDualIQ' : 'dualIQ'});
  expect(split.ConvolutionalReceiveMode).toBe('legacy-coded-asm');
});
test('noise and measured frames are explicit; no oracle equalization', () => {
  const p = finalizeTMRequest({...base, enableHChannel:true, enableEqualizer:true, equalizerMode:'mmse'});
  expect(p).toMatchObject({noiseMode:'snr', berWarmUpFrames:8, berFrames:100, excludeBERWarmUpFrames:true, equalizerMode:'blind-cma-lms',adaptiveEqualizerSamplingMode:'2sps'});
});
test('pulse-shaping bypass is explicit and limited to verified ordinary single-path modulations', () => {
  for (const modType of ['BPSK', 'QPSK', '8PSK', '16QAM', '32QAM', '16APSK', '32APSK']) {
    expect(finalizeTMRequest({
      ...base,
      modType,
      PulseShapingFilter: 'none',
    }).PulseShapingFilter).toBe('none');
  }
  expect(finalizeTMRequest({
    ...base,
    PulseShapingFilter: 'RRC',
  }).PulseShapingFilter).toBe('root raised cosine');
  expect(() => finalizeTMRequest({
    ...base,
    modType: 'MSK',
    PulseShapingFilter: 'none',
  })).toThrow('专用波形前端');
  expect(() => finalizeTMRequest({
    ...base,
    DataPathMode: 'dualIQ',
    PulseShapingFilter: 'none',
  })).toThrow('合路');
});
test.each(['OQPSK','UQPSK'])('%s accepts RRC/none on combined TM and rejects unverified split choices', modType => {
  for (const PulseShapingFilter of ['root raised cosine','none']) {
    expect(finalizeTMRequest({...base,modType,PulseShapingFilter}).PulseShapingFilter).toBe(PulseShapingFilter);
  }
  for (const PulseShapingFilter of ['none']) {
    expect(() => finalizeTMRequest({...base,modType,PulseShapingFilter,PCMFormat:'NRZ-L',DataPathMode:modType === 'UQPSK' ? 'unequalDualIQ' : 'dualIQ'})).toThrow('合路');
  }
});

test.each(['QPSK','OQPSK','UQPSK'])('RC is explicitly rejected for %s instead of silently becoming RRC', modType => {
  expect(() => finalizeTMRequest({...base,modType,PulseShapingFilter:'RC'})).toThrow('当前不在支持范围');
});

test('unsupported choices cannot be silently changed', () => {
  expect(() => finalizeTMRequest({...base, modType:'MSK',DataPathMode:'dualIQ'})).toThrow('合路');
  expect(() => finalizeTMRequest({...base, channelCoding:'TPC',DataPathMode:'dualIQ'})).toThrow('合路');
  expect(() => finalizeTMRequest({...base,sps:7})).toThrow('偶数');
  expect(() => finalizeTMRequest({...base,modType:'GMSK',enableHChannel:true,enableEqualizer:true})).toThrow('专用前端');
  expect(constellationExplanation('MSK')).toContain('十字形');
});
