classdef HelperDopplerShift < comm.internal.Helper
    %HelperDopplerShift Apply sinusoidal Doppler shift to input signal
    %
    %   Note: This is a helper function and its API and/or functionality
    %   may change in subsequent releases.
    %
    %   DSO = HelperDopplerShift creates a sinusoidal varying frequency
    %   offset System object, DSO. This object applies phase and frequency
    %   offsets to an input signal.
    %
    %   Step method syntax:
    %
    %   [Y,PHASE] = step(DSO,X) applies phase and frequency offsets to
    %   input X, and returns Y and phase offset added to each sample in
    %   PHASE. The input X is a double precision column vector of length M.
    %   M is the number of time samples in the input signals. The data type
    %   and dimensions of X and Y are the same.
    %
    %   HelperDopplerShift properties:
    %
    %   DopplerRate           - Rate of change of frequency offset in
    %                           Hz/sec 
    %   PeakDoppler           - Maximum Doppler shift in Hz
    %   SampleRate            - Sample rate

    %   Copyright 2021-2022 The MathWorks, Inc.

    % Public, non-tunable properties
    properties(Nontunable)
        %DopplerRate Doppler rate in Hertz/sec
        % Specify the rate of change of Doppler shift in Hertz/sec. The
        % Doppler shift is modeled in a sinusoidal variation with a period
        % that results in Doppler rate. This property is nontunable.
        DopplerRate = 1145
        %PeakDoppler Peak Doppler in Hertz
        %   Specify the maximum Doppler shift in Hertz. The Doppler shift
        %   will vary between +/- peak Doppler. This property is
        %   nontunable.
        PeakDoppler = 22220
        %SampleRate Sample rate in Hertz
        %   Specify the sample rate of the input samples in Hz as a double
        %   precision, real, positive scalar.  This property is nontunable.
        SampleRate = 20e6
    end
 

    % Pre-computed constants
    properties(Access = private)
        pSampleIndex = 0
    end

    methods
        % Constructor
        function obj = HelperDopplerShift(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end

    end

    methods(Access = protected)
        %% Common functions

        function [y,phase] = stepImpl(obj,u)
            % Implement algorithm. Calculate y as a function of input u and
            % discrete states.
            numSamples = length(u);
            ph = sin(obj.DopplerRate*(obj.pSampleIndex:obj.pSampleIndex+numSamples-1)/(obj.PeakDoppler*obj.SampleRate));
            phase = 2*pi*(obj.PeakDoppler^2)/obj.DopplerRate*ph;
            obj.pSampleIndex = obj.pSampleIndex + numSamples;
            % obj.pPhaseIntroducer.PhaseOffset = phases(:);
            y = u(:).*exp(1j*phase(:));
        end

        function resetImpl(obj)
            % Initialize / reset discrete-state properties
            obj.pSampleIndex = 0;
        end

        %% Backup/restore functions
        function s = saveObjectImpl(obj)
            % Set properties in structure s to values in object obj

            % Set public properties and states
            s = saveObjectImpl@matlab.System(obj);
            if isLocked(obj)
              s.pSampleIndex = obj.pSampleIndex;
            end
        end

        function loadObjectImpl(obj,s,wasLocked)
            % Set properties in object obj to values in structure s
            if wasLocked(obj)
               obj.pSampleIndex = s.pSampleIndex;
            end
            % Set public properties and states
            loadObjectImpl@matlab.System(obj,s,wasLocked);
        end
    end

     % Static Methods
   methods(Static,Access=protected)
    function groups = getPropertyGroupsImpl
      groups = matlab.system.display.Section(...
        'Title', 'Parameters',...
        'PropertyList', {'DopplerRate', 'PeakDoppler', ...
        'SampleRate'});
    end
  end
end
