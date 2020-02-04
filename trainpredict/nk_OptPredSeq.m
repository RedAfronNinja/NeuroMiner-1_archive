function [ IN, optD, optCrit ] = nk_OptPredSeq(D, L, PredGroups, IN, C, nCutOff, Lims, Crit, Ddesc)
% =====================================================================================
% FORMAT function R = nk_OptPredSeq(D, L, PredGroups, IN, C nCutOff, Lims, Crit, Ddesc)
% =====================================================================================
% This function optimizes the sequential combination of predictive models by ranking 
% cases according to predictive scores and testing different percentile thresholds for 
% passing ranked cases on to the next predictive model. The optimized model consists of 
% the learned sequence and the respective optimal upper/lower percentile thresholds for 
% case propagation at each predictive node in the sequence.
%
% Inputs:
% -------
% D :           Predictive score matrix, where each column contains the
%               predictive output of a model and each row the output of all 
%               models for a single case
% L :           The label vector
% PredGroups :  Vector indicating to which examination node each decision score
%               belongs.
% IN [ opt ]:   A previously learned sequence model that should be
%               applied to new data (see outputs).
% C :           Sequences of predictive models to be tested. Each column
%               in C is a predictive model output stored in D, 
%               each row is model sequence
% nCutOff [opt]:No. of thresholds to be tested x 2 (starting from 50%) 
% Lims [opt]:   Lower [ Lims(1) ] and upper [ Lims(2) ] percentile threshold bounds
% Crit [opt] :  The optimization criterion such as BAC
% Ddesc [opt] : a description of the nodes in the prediction sequence
%
% Output:
% -------
% IN :           Optimization results structure consisting of the following
%                fields:
% IN.OPT :
% IN.D :
% IN.optD :
% IN.Nremain :
% IN.Crit :
% IN.(Crit) :
% IN.examsfreq :
% IN.fcnt :
% _________________________________________________________________________
% (c) Nikolaos Koutsouleris, 12/2019
global VERBOSE SVM

if ~exist('IN','var') || isempty(IN)
    
    % Train sequence predictor
    if ~exist('PredGroups','var')   || isempty(PredGroups), PredGroups = 1:size(D,2); else, PredGroups = PredGroups'; end
    if ~exist('nCutOff','var')      || isempty(nCutOff),    nCutOff = 5; end
    if ~exist('Crit','var')         || isempty(Crit),       Crit = 'BAC'; end
    if ~exist('Ddesc','var')        || isempty(Ddesc),      
        Ddesc = cellstr([repmat('Model ',size(D,2),1) num2str((1:size(D,2))')]); 
    elseif numel(Ddesc) ~= size(D,2)
        error('Model descriptor entries should correspond to the number of models in the model matrix');
    end

    nC = size(C,1); m = size(D,1);
    optCrit = []; cnt=1;

    % Loop through candidate prognostic workflows
    for j=1:nC

        % Get current examination indices for current sequence
        Cj = C(j,~isnan(C(j,:))); 
        uC = unique(Cj);
        jC = false(1,numel(PredGroups)); % Create empty logical
        % Loop through unique examination nodes and assign decision scores
        % to those 
        for jj=1:numel(uC)               
            ind_jC = PredGroups == uC(jj);
            jC(ind_jC) = true;
        end
        
        if VERBOSE, fprintf('\n\n');cprintf('black*','Working on model sequence %g/%g:', j, nC); cprintf('blue','\t%s ', strjoin(Ddesc(jC),', ')); end

        % Get model outputs for given sequence in C
        jD = D(:,jC);       % Get decision scores for current sequence
        nD = size(jD,2);    % Number of prediction nodes
        
        % Build threshold vectors
        switch SVM.SEQOPT.AnchorType
            case 1 % Flexible anchoring based on the decision boundaries of the models. This is for classification models only
                Anchor = sum(jD < 0) * 100 / m; LL=zeros(numel(Anchor),1); UL=LL;
                for z=1:nD % Loop through models
                    Lthr = jD( jD(:,z) < 0, z ); % find subjects below the boundary
                    pLthr = percentile(Lthr, 100 - Lims(1)); LL(z) = sum(jD(:,z) <= pLthr)*100/m; % Compute lower percentile for case propagation
                    Uthr = jD( jD(:,z) > 0, z ); % find subjects above the boundary
                    pUthr = percentile(Uthr, Lims(2)); UL(z) = sum(jD(:,z) <= pUthr)*100/m; % Compute upper percentile for case propagation
                end
            case 2 % Fixed percentile anchoring starting at the median
                Anchor = repmat(50,1,nD); % Define the median for all models
                LL = Anchor - Lims(1); % lower percentile for case propagation 
                UL = Anchor + Lims(2); % upper percentile for case propagation
        end
        
        % Prepare the threshold vectors for the upper and lower percentile
        % bounds using nCutOffs parameter (stepping param)
        vecneg = cell(nD,1); vecpos = cell(nD,1);
       
        for z=1:nD % Loop through models
            % Lower percentile vector
            vecneg{z} = Anchor(z): -((Anchor(z)-LL(z)) / nCutOff) : LL(z); 
            if isempty(vecneg{z}), vecneg{z} = Anchor(z) : -(Anchor(z)/nCutOff) : 0; end
            vecneg{z}(1)=[];
            % Upper percentile vector
            vecpos{z} = Anchor(z):  (UL(z)-Anchor(z)) / nCutOff : UL(z); 
            if isempty(vecpos{z}), vecneg{z} = Anchor(z) : 100-Anchor(z)/nCutOff : 100; end
            vecpos{z}(1)=[]; 
        end
        
        % Model performance of first model in sequence
        OPT = feval(Crit,L,jD(:,1));

        % Prepare results container for optimization
        tIN = struct('Sequence', Cj, ...
                'Sequence2Feats', jC, ...
                'OPT', OPT, ... 
                'fcnt', 1, ...
                'D', jD, ...
                'optD', jD(:,1), ...
                'Nremain', ones(m,1), ...
                'Crit', Crit, ...
                'allOPTs', OPT, ...
                'diffOPTs', 0, ...
                'optlvec', 0, ...
                'optuvec', 0, ...
                'optlthr', 0, ...
                'optuthr', 0);
        tIN.(Crit)(1) = OPT;
        tIN.vecneg = vecneg;
        tIN.vecpos = vecpos;
        
        % Run sequential optimization
        for i=1:nD-1, tIN = OptPredSeq(tIN, i, L, Crit); end
        
        % Analyze optimized sequence:
        tIN.uN = unique(tIN.Nremain)';       % unique sequence node positions among cases
        tIN.AnalSeq = Cj(tIN.uN);            % optimized node sequence
        tIN.AnalSeqDesc = Ddesc(Cj(tIN.uN)); % description of optimized node sequence
        % Node examination frequencies
        tIN.examsfreq = zeros(1,numel(tIN.Sequence)); 
        for i=1:numel(tIN.Sequence)
            tIN.examsfreq(i) = sum(tIN.Nremain == i)*100/m;
        end
        if VERBOSE, fprintf('\nOptimized sequence performance: %1.2f', tIN.(Crit)(end)); end
        if j==1, optCrit = tIN.OPT; IN = tIN; end
       
        if tIN.(Crit)(end) > optCrit(end)
            if VERBOSE, fprintf('\n');cprintf('blue*','+++ New optimal sequence: %s ', strjoin(Ddesc(jC),', ')); end
            IN = tIN; 
            cnt = cnt +1;
            optCrit(cnt) = IN.OPT(end);
        end
    end
    optD = IN.optD;
    
else
    % Apply trained sequence predictor to data
    D = D(:,IN.AnalSeq);
    Nremain = ones(size(D,1),1);
    optD = D(:,1);
    % if labels are available compute performance at first node.
    if exist('L','var') && ~isempty(L), lbmode = true; else, lbmode = false; end
    if lbmode 
        IN.SeqPerfGain_test = zeros(1, numel(IN.AnalSeq));
        IN.SeqPerfGain_test(1) = feval(IN.Crit,L,D(:,1));
    end
    for j=1:numel(IN.AnalSeq)-1
        % Apply absolute thresholds (questionable whether this is the best
        % strategy or alternatively apply learned percentiles)
        fI = find(Nremain==j);
        lthr = IN.optlthr(j); uthr = IN.optuthr(j);
        ind = D(fI,j) >= lthr & D(fI,j) <= uthr;
        Nremain(fI(ind)) = j+1;
        optD = replace_predictions(D(:,1:j), optD, D(:,j+1), fI(ind), SVM.SEQOPT.ReplaceMode);
        optD(fI(ind)) = D(fI(ind),j+1);
        if lbmode 
            % Compute performance gains at each node
            IN.SeqPerfGain_test(j+1) = feval(IN.Crit,L,optD);
        end
    end
    % and compute final sequence performance gain if labels have been provided
    if lbmode, optCrit = IN.SeqPerfGain_test(end); end
    IN.Nremain_test = Nremain;
end
% _________________________________________________________________________
function R = OptPredSeq(R, I, L, Crit)
global VERBOSE SVM

if isempty(VERBOSE), VERBOSE = true; end

optuvec = R.vecpos{I}(end);
optlvec = R.vecneg{I}(1);
optD = R.optD;
optRemain = R.Nremain;
fI = find(R.Nremain==I);
if isempty(fI) 
    cntx = 1;
    while isempty(fI)
        fI = find(R.Nremain==I-cntx);
        cntx=cntx+1;
    end
end
rOPT = R.OPT;
allOPT = rOPT;
if VERBOSE, fprintf('\nProcessing: %g cases in predictive workflow node %g: ', numel(fI), I); end
DI = R.D(:,I);
warning off

% Loop through upper and lower boundaries, thus increasing the propagation
% population in every iteration
for j=1:numel(R.vecneg{I})
    
    jD = R.optD;
    jDI = DI(fI); jDI(isnan(jDI))=[];
    %% Defined thresholds for case propagation using percentile method
    lthr = percentile(jDI, R.vecneg{I}(j));
    uthr = percentile(jDI, R.vecpos{I}(j));
    if ~exist('optuthr','var')
         optlthr = lthr; optuthr = uthr;
    end
    ind = jDI >= lthr & jDI <= uthr;
    if ~any(ind), continue; end
    jNremain = R.Nremain;
    fII = fI(ind);
    jNremain(fII) = I+1; 
    
    %% Compute performance metric of next propagation compared to current node in the sequence
    switch SVM.SEQOPT.Mode
        case 1
            % Here optimization will be done using the performance in the 
            % actual set of cases selected based on the current ambiguity 
            % threshold
            nD = replace_predictions(R.D(:,1:I), jD, R.D(:,I+1),fII, SVM.SEQOPT.ReplaceMode); 
            tL = L(fII); % get the labels
            switch SVM.SEQOPT.PerfMode
                case 1 % based on prediction performance criterion 
                    prevOPT = feval(Crit,tL,jD(fII));   % get current performance
                    ijOPT = feval(Crit,tL,nD(fII));     % get performance if predictions of cases to be propagated (based on fII) are replaced with predictions of next model in the chain
                case 2 % based on decision distance change
                    t_jD = jD(fII); t_nD = nD(fII);
                    prevOPT = mean(t_jD(tL==1)) - mean(t_jD(tL==-1)); % this is the current decision distance between cases to be propagated
                    ijOPT = mean(t_nD(tL==1)) - mean(t_nD(tL==-1));   % this is the decision distance after propagated cases receive predictions of next model
            end
            jD(fII) = nD(fII);
        case 2
            % Alternatively optimization is done on the entire population
            % (at the various levels of classifier propagation)
            prevOPT = rOPT;
            jD = replace_predictions(R.D(:,1:I), jD, R.D(:,I+1), fII, SVM.SEQOPT.ReplaceMode);
            switch SVM.SEQOPT.PerfMode
                case 1
                    ijOPT = feval(Crit,L,jD);
                case 2
                    ijOPT = mean(jD(L==1)) - mean(jD(L==-1));
            end
    end
    %% Evaluate next propagation step
    if ijOPT > prevOPT
        optlvec     = R.vecneg{I}(j);
        optuvec     = R.vecpos{I}(j);
        optlthr     = lthr; 
        optuthr     = uthr;
        optRemain   = jNremain;
        rOPT        = ijOPT;
        optD        = jD;
        allOPT      = feval(Crit,L,jD);
        if VERBOSE, fprintf('\nNext Node %g: %1.2f [%4g cases; Lower thresh: %1.2f, Upper thresh: %1.2f]', ...
                I+1, rOPT.(Crit), numel(fI(ind)), lthr, uthr); end
    else
        if VERBOSE, fprintf('.'); end
    end
end

R.optlvec(I) = optlvec;
R.optuvec(I) = optuvec;
R.optlthr(I) = optlthr;
R.optuthr(I) = optuthr;
R.optD = optD;
R.Nremain = optRemain;
R.jOPT(I) = rOPT;
R.allOPTs(I) = allOPT;
R.diffOPTs(I) = allOPT - R.OPT;
R.OPT = allOPT;

% _________________________________________________________________________
function D_new = replace_predictions(D, D_opt, D_next, I_next, ActMode)
        
D_new = D_opt;
switch ActMode
    case 1 % simple replacement 
        D_new(I_next) = D_next(I_next);
    case 2 % ensemble-based fusioning
        D_new(I_next) = nm_nanmean( [ D(I_next,:) D_next(I_next,:) ], 2 );
end