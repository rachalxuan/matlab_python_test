// Generate requests using the actual browser contract, for the MATLAB test.
const fs = require('fs');
const path = require('path');
const Module = require('module');
const root = path.resolve(__dirname, '../../..');
const contractPath = path.join(root, 'src/pages/MatlabFFT/parameterContract.js');
const {code} = require('@babel/core').transformFileSync(contractPath, {
  babelrc: false, configFile: false,
  plugins: ['@babel/plugin-transform-modules-commonjs'],
});
const contract = new Module(contractPath, module);
contract.filename = contractPath;
contract.paths = module.paths;
contract._compile(code, contractPath);
const requests = ['16APSK','32APSK'].map((modType, i) => {
  const direct = {
    modType, DataPathMode:'single', symbolRate:10e6, sps:8,
    PulseShapingFilter:'root raised cosine', RolloffFactor:0.35, FilterSpanInSymbols:10,
    channelCoding:'none', NumBytesInTransferFrame:256, hasASM:true,
    RandomizerEnabled:false, berWarmUpFrames:8, berFrames:16, excludeBERWarmUpFrames:true,
    noiseMode:'off', snr:100, cfo:0, phaseOffset:0, delay:0,
    enableHChannel:false, enableEqualizer:false, debugUQPSKTimingInputNormalization:false,
    enableReceiverTimeline:true, includeRawData:true, remoteMode:false, showFigures:false,
    randomSeed:2026092508+i,
  };
  return {Direct:direct, Web:contract.exports.finalizeTMRequest(direct)};
});
const destination = process.argv[2];
if (!destination) throw new Error('Provide a destination JSON path.');
fs.writeFileSync(destination, JSON.stringify(requests, null, 2));
console.log(`Wrote ${requests.length} real frontend requests to ${destination}`);
