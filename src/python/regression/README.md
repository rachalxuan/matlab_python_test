# CCSDS TM Regression Tests

This folder contains lightweight MATLAB regression checks for the CCSDS TM
simulation chain.

Run all checks from MATLAB:

```matlab
cd('E:/web_code/react/fft_project/react-fft/src/python/regression');
allResults = run_all_regression();
```

Or run one group:

```matlab
results = reg_pcm_phase_sweep();
results = reg_h_channel_sweep();
results = reg_4d_tcm_sweep();
results = reg_coding_smoke();
```

The tests are intentionally small and use `showFigures=false`. They are meant
to catch regressions after receiver, synchronization, H-channel, or decoder
changes, not to replace long performance sweeps.
