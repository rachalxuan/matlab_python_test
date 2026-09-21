import { finalizeTMRequest, codingDefaults, constellationExplanation } from './parameterContract';
const base = { modType: 'QPSK', channelCoding: 'none', sps: 8, hasASM: true, DataPathMode: 'single', NumBytesInTransferFrame: 1151 };
test.each(['16APSK','32APSK'])('%s uses pilotless ordinary TM, no FACM leftovers', modType => {
  const p = finalizeTMRequest({...base, modType, HasTMAPSKPilots: true, enableFACMEqualizer: true, acmFormat: 21});
  expect(p).toMatchObject({WaveformMode:'ordinaryTM', HasTMAPSKPilots:false, APSKReceiverMode:'pilotless'});
  expect(p.enableFACMEqualizer).toBeUndefined();
});
test('concatenation checks RS encoded bits, not information bytes', () => {
  const p = {...base, channelCoding:'concatenated', RSMessageLength:223, RSInterleavingDepth:5, NumBytesInTransferFrame:1115};
  expect(() => finalizeTMRequest({...p, ConvolutionalCodeRate:'5/6'})).toThrow('10232 bit');
  expect(() => finalizeTMRequest({...p, ConvolutionalCodeRate:'1/2'})).not.toThrow();
  expect(() => finalizeTMRequest({...p, RSInterleavingDepth:1, ConvolutionalCodeRate:'7/8'})).not.toThrow();
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
test('unsupported choices cannot be silently changed', () => {
  expect(() => finalizeTMRequest({...base, modType:'MSK',DataPathMode:'dualIQ'})).toThrow('合路');
  expect(() => finalizeTMRequest({...base, channelCoding:'TPC',DataPathMode:'dualIQ'})).toThrow('合路');
  expect(() => finalizeTMRequest({...base,sps:7})).toThrow('偶数');
  expect(() => finalizeTMRequest({...base,modType:'GMSK',enableHChannel:true,enableEqualizer:true})).toThrow('专用前端');
  expect(constellationExplanation('MSK')).toContain('十字形');
});
