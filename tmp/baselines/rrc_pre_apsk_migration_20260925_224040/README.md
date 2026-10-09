# RRC pre-APSK-migration baseline

This directory freezes the No-H RRC behavior before later APSK interface changes.
Each case MAT contains Parameters, Result, ConsoleLog, and Result.BaselineCapture.
BaselineCapture contains the full TX waveform, reference constellation, raw RX symbols, coarse waveform, timing output, fine-carrier output, and resolved configuration.
summary.csv is the quick comparison index; source_snapshot preserves the relevant MATLAB source.
The UQPSK timing-input normalization diagnostic is OFF in every case.
