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
  const p = finalizeTMRequest({...base, modType, HasTMAPSKPilots: true, enableFACMEqualizer: true, acmFormat: 21});
  expect(p).toMatchObject({WaveformMode:'ordinaryTM', HasTMAPSKPilots:false, APSKReceiverMode:'pilotless'});
  expect(p.enableFACMEqualizer).toBeUndefined();
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
test('ordinary single-path modulations use one continuous convolutional receiver for every verified RS/rate profile', () => {
  for (const modType of ['QPSK', '8PSK', '16QAM', '32QAM']) {
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
test('coding switches clear stale K and select compatible concatenation', () => {
  expect(codingDefaults('Turbo').NumBitsInInformationBlock).toBe(3568);
  expect(codingDefaults('LDPC').NumBitsInInformationBlock).toBe(1024);
  expect(codingDefaults('concatenated').ConvolutionalCodeRate).toBe('1/2');
  expect(() => finalizeTMRequest({...base, channelCoding:'Turbo',NumBitsInInformationBlock:1024})).toThrow('Turbo');
});
test('noise and measured frames are explicit; no oracle equalization', () => {
  const p = finalizeTMRequest({...base, enableHChannel:true, enableEqualizer:true, equalizerMode:'mmse'});
  expect(p).toMatchObject({noiseMode:'snr', berWarmUpFrames:8, berFrames:100, excludeBERWarmUpFrames:true, equalizerMode:'blind-cma-lms',adaptiveEqualizerSamplingMode:'2sps'});
});
test('pulse-shaping bypass is explicit and limited to verified ordinary single-path modulations', () => {
  for (const modType of ['BPSK', 'QPSK', '8PSK', '16QAM', '32QAM']) {
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
test.each(['OQPSK','UQPSK'])('%s accepts three combined-TM pulses and rejects unverified split choices', modType => {
  for (const PulseShapingFilter of ['root raised cosine','raised cosine','none']) {
    expect(finalizeTMRequest({...base,modType,PulseShapingFilter}).PulseShapingFilter).toBe(PulseShapingFilter);
  }
  for (const PulseShapingFilter of ['raised cosine','none']) {
    expect(() => finalizeTMRequest({...base,modType,PulseShapingFilter,PCMFormat:'NRZ-L',DataPathMode:modType === 'UQPSK' ? 'unequalDualIQ' : 'dualIQ'})).toThrow('合路');
  }
});

test('RC is not accidentally enabled on an unverified frontend', () => {
  expect(() => finalizeTMRequest({...base,modType:'QPSK',PulseShapingFilter:'RC'})).toThrow('OQPSK/UQPSK');
});

test('unsupported choices cannot be silently changed', () => {
  expect(() => finalizeTMRequest({...base, modType:'MSK',DataPathMode:'dualIQ'})).toThrow('合路');
  expect(() => finalizeTMRequest({...base, channelCoding:'TPC',DataPathMode:'dualIQ'})).toThrow('合路');
  expect(() => finalizeTMRequest({...base,sps:7})).toThrow('偶数');
  expect(() => finalizeTMRequest({...base,modType:'GMSK',enableHChannel:true,enableEqualizer:true})).toThrow('专用前端');
  expect(constellationExplanation('MSK')).toContain('十字形');
});
