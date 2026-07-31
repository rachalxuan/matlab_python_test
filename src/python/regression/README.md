# CCSDS TM Regression Tests

This folder contains the checkpointed CCSDS TM regression runner, one common
PASS evaluator, and the formal 18-case smoke catalog.

## Dual-I/Q bit contract

Run the fast channel-free I/Q contract before a system sweep:

```matlab
cd('E:/web_code/react/fft_project/react-fft/src/python/regression');
report = run_tm_data_path_contract_tests();
```

The default `quick` profile checks exact bit packing and frame merge order,
the supported modulation and coding dimensions, randomization before/after
convolutional coding, and unsupported-mode guards. It does not pass through
AWGN, CFO, timing synchronization, an H channel, or the equalizer.

The supported modulation-by-coding cross product can be checked with:

```matlab
report = run_tm_data_path_contract_tests(struct('Profile','full'));
```

This `full` contract remains channel-free; use `run_tm_data_path_sweep` for
end-to-end RF and BER checks. The capability catalog used by both the
generator guard and the tests is `tm_data_path_capabilities.m`.

## Formal smoke regression

List the smoke plan without running simulations:

```matlab
cd('E:/web_code/react/fft_project/react-fft/src/python/regression');
T = run_smoke_regression(struct('DryRun',true));
```

Run one short case:

```matlab
opts = struct( ...
    'RunId','smoke_check', ...
    'CaseIds',"smoke.qpsk.none.single", ...
    'FailOnFailure',true);
T = run_smoke_regression(opts);
```

Run or resume all 18 cases:

```matlab
opts = struct('RunId','smoke_baseline_v2','Resume',true);
T = run_smoke_regression(opts);
```

Generated checkpoints and summaries go to `artifacts/ccsds/` by default and
are ignored by Git. Reusing the same `RunId` resumes terminal cases by stable
case ID. If parameters, thresholds, or case metadata change, the runner
requires a new `RunId` rather than mixing incompatible results.

Checkpoints use metrics-only storage: case definitions, deterministic seeds,
statuses, scalar BER/FER/lock and I/Q diagnostics, timing, and errors are
retained, while waveform, spectrum, constellation, and pipeline arrays are
not persisted. Resuming an older checkpoint automatically migrates its scalar
results and rewrites it in the compact format before new cases run.

The four duplicate standalone regression scripts were removed after the
version-1 baseline passed all 18 cases. `run_all_regression.m` remains a
legacy broad exploratory sweep and is not part of the formal smoke suite.
