function [TFR, groupTFR] = compute_TFR(FT_EEG,new_fsample,frequencies,FT_or_tfdecomp)
% compute_TFR is an internal function of the ADAM toolbox. It takes standard FT input and computes
% single trial TFR for MVPA and separate group TFRs (no single trial data) for Hanning and
% multitaper FT_EEG is standard fieldtrip struct new_fsample is the frequency to which the output
% should be downsampled (if left empty, output has the same sr as the input freqs is a specification
% of the frequencies to include. You can modify the function below if you want to use your own
% parameters to compute the TFRs.
%
% Internal function of the ADAM toolbox by J.J.Fahrenfort, 2015, 2016, 2018
%
% See also: ADAM_MVPA_FIRSTLEVEL, CLASSIFY_TFR_FROM_EEGLAB_DATA, COMPUTE_TFR_FROM_FT_EEG

switch FT_or_tfdecomp
    
    case 'FT'

        if nargin<3
            frequencies = 2:2:100;
        end
        if isempty(frequencies)
            frequencies = 2:2:100;
        end

        % what is current sampling rate?
        fsample = round((numel(FT_EEG.time)-1)/(FT_EEG.time(end)-FT_EEG.time(1)));

        % downsample_factor specifies the factor by which to downsample
        if nargin < 2
            new_fsample = 0;
        end
        if ischar(new_fsample)
            new_fsample = string2double(new_fsample);
        end
        if new_fsample == 0
            new_fsample = fsample;
        end

        downsample_factor = fsample/new_fsample;
        % check if downsample_factor is an integer
        if ~(floor(downsample_factor)==downsample_factor)
            downsample_factor = round(downsample_factor);
            disp('WARNING: Specified new sampling frequency resulted in non-integer downsample_factor: rounding off new sampling rate to prevent interpolation. Next time you better pick a sampling rate that fits.');
        end
        % times of interest, possibly better to keep actual time points than to create new time series
        if iscell(FT_EEG.time)
            toi = downsample(FT_EEG.time{1},downsample_factor); 
        else
            toi = downsample(FT_EEG.time,downsample_factor); 
        end

        % windows and cycles of interest (use appproximate time-window of .5 up to
        % 30 Hz, above that, we use frequency-dependent time-window, by keeping the
        % cycles constant at 15) 
        % Few cycles: good temporal, poor frequency precision, Many cycles: bad temporal, good frequency precision
        % low frequencies: few cycles, high frequencies: many cycles
        for cFreq=1:numel(frequencies)
            for cCycle=1:100
                tim_winspace(cFreq,cCycle) = cCycle/frequencies(cFreq);
                % we use a time window of approx .5 seconds to keep temporal
                % resolution high in the lower frequencies
                % then from 30 Hz onwards we keep the nr of cycles constant to
                % increase temporal resolution
                act_cyclespace(cFreq) = nearest(tim_winspace(cFreq,:),.5); 
                act_ftimwin(cFreq) = tim_winspace(cFreq,act_cyclespace(cFreq));
            end
        end

        % get single condition data for group analysis
        condlabels = unique(FT_EEG.trialinfo);
        for c = 1:numel(condlabels)
            cfg              = [];
            cfg.trials       = FT_EEG.trialinfo == condlabels(c);
            % turn off annoying FT warnings
            if exist('ft_warning','file') == 2
                ft_warning off;
            end
            FT_COND{c}       = ft_selectdata(cfg,FT_EEG);
        end

        % Hanning taper for low frequencies
        cfg              = [];
        cfg.output       = 'pow';
        %cfg.channel      = 'EEG';
        cfg.method       = 'mtmconvol';
        cfg.taper        = 'hanning';
        cfg.foi          = frequencies(frequencies<=30);  % analysis 2 to 30 Hz in steps of 2 Hz
        cfg.t_ftimwin    = act_ftimwin(frequencies<=30);  % repmat(.5,1,numel(cfg.foi));   % length of time window = 0.5 sec 
        cfg.toi          = toi;                           % the times around which TFRs are computed, determined by downsample_factor
        cfg.pad          = 'maxperlen';
        if ~isempty(cfg.foi)
            % single trial
            cfg.keeptrials   = 'yes';
            % turn off annoying FT warnings
            if exist('ft_warning','file') == 2
                ft_warning off;
            end
            TFRhann          = ft_freqanalysis(cfg, FT_EEG);
            TFRhann.cumtapcnt = TFRhann.cumtapcnt(1,:); % remove redundant information, number of tapers is the same for each trial
            % also get condition data on group level
            for c = 1:numel(condlabels)
                cfg.keeptrials   = 'no';
                %groupTFRhann.(['cond_' num2str(condlabels(c))])  = ft_freqanalysis(cfg, FT_COND{c});
                % turn off annoying FT warnings
                if exist('ft_warning','file') == 2
                    ft_warning off;
                end
                groupTFRhann{c}  = ft_freqanalysis(cfg, FT_COND{c});
            end
            cfg = [];
            cfg.parameter  = 'powspctrm';
            groupTFRhann = ft_appendfreq(cfg,groupTFRhann{:});
        end

        % multitaper for higher frequencies
        cfg = [];
        cfg.output     = 'pow';
        % cfg.channel    = 'EEG';
        cfg.method     = 'mtmconvol';
        cfg.taper      = 'dpss';
        cfg.foi        = frequencies(frequencies>30);
        cfg.t_ftimwin  = 15./cfg.foi; % -> this decreases window size for higher freqs, keeping cycles constant at 15
        cfg.tapsmofrq  = 0.1 * cfg.foi; % -> this increases frequency smoothing for higher freqs
        %cfg.t_ftimwin  = repmat(.4,numel(cfg.foi),1); % -> keeps window size constant at .4 as in PNAS paper
        %cfg.tapsmofrq  = 10; % -> keeps frequency smoothing constant at 20 Hz -> result: 7 tapers as in PNAS paper
        cfg.toi        = toi;
        cfg.pad        = 'maxperlen';
        cfg.keeptrials = 'yes';
        if ~isempty(cfg.foi)
            cfg.keeptrials   = 'yes';
            TFRmult        = ft_freqanalysis(cfg, FT_EEG);
            TFRmult.cumtapcnt = TFRmult.cumtapcnt(1,:); % remove redundant information, number of tapers is the same for each trial
            % also get condition data on group level
            for c = 1:numel(condlabels)
                cfg.keeptrials   = 'no';
                groupTFRmult{c}  = ft_freqanalysis(cfg, FT_COND{c});
            end
            cfg = [];
            cfg.parameter  = 'powspctrm';
            groupTFRmult = ft_appendfreq(cfg,groupTFRmult{:});
        end

        % free up memory
        clear FT_EEG FT_COND;

        % get relevant part of the spectrum
        if exist('TFRhann','var')
            TFR             = TFRhann; 
        else
            TFR             = TFRmult;
        end
        % if both exist, merge the results
        if exist('TFRhann','var') && exist('TFRmult','var')
            cfg.parameter  = 'powspctrm';
            cfg.appenddim  = 'freq';
            TFR = ft_appendfreq(cfg,TFRhann,TFRmult);
            TFR.trialinfo = TFRhann.trialinfo;
        end
        % finally cut out annoying NaNs due to padding, a bit complex due to unknown format
        dims = regexp(TFR.dimord, '_', 'split');
        chandim = find(strcmp(dims,'chan'));
        timedim = find(strcmp(dims,'time'));
        trialdim = find(strcmp(dims,'rpt'));
        freqdim = find(strcmp(dims,'freq'));
        index    = cell(1, ndims(TFR.powspctrm));
        index(:) = {':'};
        index{chandim} = 1;
        index{trialdim} = 1;
        index{timedim} = find(~isnan(squeeze(sum(TFR.powspctrm(index{:}),freqdim))));
        index{chandim} = ':';
        index{trialdim} = ':';
        TFR.powspctrm = TFR.powspctrm(index{:});
        % and also correct time
        TFR.time = TFR.time(index{timedim});

        % same for group
        if exist('groupTFRhann','var')
            groupTFR             = groupTFRhann; 
        else
            groupTFR             = groupTFRmult;
        end
        % if both exist, merge the results
        if exist('groupTFRhann','var') && exist('groupTFRmult','var')
            cfg.parameter  = 'powspctrm';
            cfg.appenddim  = 'freq';
            groupTFR = ft_appendfreq(cfg,groupTFRhann,groupTFRmult);
        end
        groupTFR.powspctrm = groupTFR.powspctrm(index{:});
        % and also correct time and add trialinfo
        groupTFR.time = groupTFR.time(index{timedim});
        groupTFR.trialinfo = condlabels;
        % remove cfg's to save memory and disk space
        if isfield(groupTFR,'cfg')
            groupTFR = rmfield(groupTFR,'cfg');
        end
        if isfield(TFR,'cfg')
            TFR = rmfield(TFR,'cfg');
        end
    %%    
    case 'tfdecomp'
        

        %%
        cfg = [];

        cfg.channels = 1:length(FT_EEG.label);
        cfg.chanlocs = FT_EEG.label;
        
        % hard-coded part for template switch study
        cfg.times2save = -1:.025:1;
        cfg.frequencies = [frequencies(1) frequencies(end) length(frequencies)]; % from min to max in nsteps
        
        %% determine cycles
        
        cycle_space = linspace(3,12,50);
        freq_space = linspace(1,40,50);
        idx=dsearchn(freq_space',frequencies(1:2)');
        cfg.cycles = cycle_space(idx); % min max number of cycles used for min max frequency
        
        
        %%
        
        cfg.scale = 'lin'; % whether the above frequency settings will be logarithmically (recommended) or linearly scaled
        cfg.erpsubtract = false; % if true, non-phase-locked (i.e. "induced") power will be computed by subtracting the ERP from each single trial
        cfg.srate = FT_EEG.fsample;
        cfg.eegtime = FT_EEG.time;
        cfg.report_progress = true;
        cfg.save_output = false;
        
        %% first single trial raw power on all trials
        
        eegdat = {permute(FT_EEG.trial,[2 3 1])};
        cfg.singletrial = true;
        [tf_pow,~,dim] = tfdecomp(cfg,eegdat);
        
        % --> make FT struct out of it:
        TFR.freq= dim.freqs;
        TFR.label= FT_EEG.label;
        TFR.dimord= 'rpt_chan_freq_time';
        TFR.time= dim.times;
        TFR.powspctrm= permute(tf_pow{1},[4 1 2 3]);
        TFR.cfg= cfg;
        TFR.trialinfo= FT_EEG.trialinfo;


    
        %% then divide into conditions and do trial-average with baseline correction
        
        condlabels = unique(FT_EEG.trialinfo);
        eegdat = cell(1,length(condlabels));
        for ci=1:length(condlabels)
            eegdat{ci} = permute(FT_EEG.trial(FT_EEG.trialinfo==condlabels(ci),:,:),[2 3 1]);
        end
        
        cfg.basetime = [-.5 -.2]; % pre-stim baseline
        cfg.baselinetype = 'conavg'; % 'conavg' or 'conspec'
        cfg.singletrial = false;
        
        [tf_pow,~,dim] = tfdecomp(cfg,eegdat);

        %% --> make FT struct out of it:
        groupTFR.freq= dim.freqs;
        groupTFR.label= FT_EEG.label;
        groupTFR.dimord= 'rpt_chan_freq_time';
        groupTFR.time= dim.times;
        groupTFR.powspctrm= tf_pow;
        groupTFR.cfg= cfg;
        groupTFR.trialinfo= condlabels;

end

