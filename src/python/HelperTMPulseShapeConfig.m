function cfg = HelperTMPulseShapeConfig(mode, sps, rolloff, span)
% Shared pulse definitions only; modulation, timing and soft decisions stay
% in their existing receivers. RC uses an RC matched filter (RC*RC overall,
% not a Nyquist RRC/RRC pair). None denotes an SPS-wide rectangular hold.
mode = lower(string(mode));
validateattributes(sps,{'numeric'},{'scalar','integer','positive'});
cfg.Mode = char(mode);
if mode == "none"
    cfg.FilterShape = '';
    cfg.OQPSKPulseShape = 'Custom';
    cfg.TransmitTaps = ones(1,sps);
    cfg.ReceiveTaps = ones(1,sps)/sps;
    cfg.TransientSymbols = 1;
    cfg.TransmitLabel = 'rectangular symbol hold (no shaping filter)';
    cfg.ReceiveLabel = 'rectangular matched filter';
else
    if mode == "root raised cosine"
        cfg.FilterShape = 'Square root';
        cfg.OQPSKPulseShape = 'Root raised cosine';
        shape = 'sqrt';
    elseif mode == "raised cosine"
        cfg.FilterShape = 'Normal';
        cfg.OQPSKPulseShape = 'Normal raised cosine';
        shape = 'normal';
    else
        error('TMPulseShape:InvalidMode','Unsupported pulse shape: %s',mode);
    end
    cfg.TransmitTaps = rcosdesign(rolloff,span,sps,shape);
    cfg.ReceiveTaps = conj(fliplr(cfg.TransmitTaps));
    cfg.TransientSymbols = span;
    cfg.TransmitLabel = char(mode);
    cfg.ReceiveLabel = char(mode + " matched filter");
end
cfg.ReceiveGroupDelaySamples = (numel(cfg.ReceiveTaps)-1)/2;
end
