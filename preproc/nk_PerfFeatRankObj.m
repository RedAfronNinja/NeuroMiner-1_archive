function IN  = nk_PerfFeatRankObj(oY, IN)
% =========================================================================
% FORMAT function IN = nk_PerfFeatRankObj(Y, IN)
% =========================================================================
% Takes input matrix Y and ranks its features according to their relevance
% for predicting IN.curlabel. The relevance vector W can be used to
% upweight (select) or downweight (remove) respective features in the
% subsequent processing steps.
%
% I/O Arguments (: Defaults): 
% -------------------------------------------------------------------------
% Y                   :     M cases x N features data matrix
% IN.curlabel         :     Target label for prediction
% IN.opt              :     Parameter optimization array
% IN.Params_desc      :     Parameter descriptions
% IN.algostr          :     Algorithm used for feature weightung
% IN.(algostr)        :     Parameter substructure for feature weighting
%                           algorithm
% IN.W                :     The ranking vector over the features
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 05/2016

global VERBOSE

% Defaults
if isempty(IN),             error('Suitable input structure is missing. See the functions'' help for more information.'); end
if ~isfield(IN,'curlabel'), error('Label vector is missing! Add a ''curlabel'' variable to your input structure.'); end
if ~isfield(IN,'algostr'),  error('No feature weighting algorithm found in the input structure. Provide one according to the function help.'); end
if isfield(IN,'curglabel') && ~isempty(IN.curglabel)
    Y = oY(IN.curglabel,:); L = IN.curlabel(IN.curglabel); 
else
    Y = oY; L = IN.curlabel;
end

Params_desc = []; opt =[]; 
if isfield(IN,'opt') && ~isempty(IN.opt), Params_desc = IN.Params_desc; opt = IN.opt; end

% Remove unlabeled subjects for supervised algorithms
if ~strcmp(IN.algostr,'idetect')
    indnan = isnan(L); if any(indnan), L(indnan) = []; Y(indnan,:)=[]; end
end

switch IN.algostr
    
    case 'varfeat'
        IN.W = var(Y);
    
    case 'idetect'
        IN.idetect.sigma = nk_ReturnParam('Sigma',Params_desc, opt); 
        IN.idetect.lambda = nk_ReturnParam('Lambda',Params_desc, opt);
        [IN.obj,IN.W] = iDetect(Y',IN.idetect); IN.W = IN.W';
        
    case 'imrelief'
        IN.imrelief.sigma = nk_ReturnParam('Sigma',Params_desc, opt); 
        IN.imrelief.lambda = nk_ReturnParam('Lambda',Params_desc, opt); 

        IN.W = IMRelief_Sigmoid_FastImple(Y', L, IN.imrelief.distance, ...
                                               IN.imrelief.sigma, ...
                                               IN.imrelief.lambda, ...
                                               IN.imrelief.maxiter, ...
                                               IN.imrelief.plotfigure, VERBOSE);
    case 'simba'
        beta = nk_ReturnParam('Beta',Params_desc, opt); 
        if ~isempty(beta)
            IN.simba.simba.extra_param.beta = beta;
        else
            IN.simba.simba.extra_param.beta = suggestBeta(Y, L);
        end

        switch IN.simba.simba.utilfunc
            case 1 % linear
                if VERBOSE, fprintf(' Simba linear'); end
            case 2 % sigmoid
                if VERBOSE, fprintf(' Simba sigmoid (beta=%g)',IN.simba.simba.extra_param.beta); end
        end

        IN.W = nk_SimbaMain(Y, L, IN.simba.simba.extra_param); IN.W = IN.W';

    case 'gflip'
        beta = nk_ReturnParam('Beta',Params_desc, opt); 
        if ~isempty(beta)
            IN.gflip.gflip.extra_param.beta = beta;
        else
            IN.gflip.gflip.extra_param.beta = suggestBeta(Y, L);
        end
        switch IN.gflip.gflip.utilfunc
            case 1
                if VERBOSE, fprintf(' G-flip zero-one'); end
            case 2
                if VERBOSE, fprintf(' G-flip linear'); end
            case 3
                if VERBOSE, fprintf(' G-flip sigmoid (beta=%g)', IN.gflip.gflip.extra_param.beta); end
        end

        [~, IN.W] = gflip(Y, L, IN.gflip.gflip.extra_param);
%   case 'lmnn'
%             IN.W = lmnn2(Y', L, DR.LMNN.k, ...
%                     'maxiter', 1000, ...
%                     'quiet',1, ...
%                     'outdim',IN.LMNN.dims, ...
%                     'mu', IN.LMNN.mu);
    case 'feast'
        if VERBOSE, fprintf(' feast'); end
        [~, IN.W] = nk_FEAST(Y, L, [], IN.FEAST);
        IN.W = IN.W';
        
    case 'auc'
        IN.W = (nk_AUCFeatRank(Y, L))'; 

    case {'pearson','spearman'}
       
        if VERBOSE, fprintf(' %s', IN.algostr); end
        IN.W = abs(nk_CorrMat(Y,L,IN.algostr));

    case 'fscore'
        if VERBOSE; fprintf(' F-Score'); end
        IN.W = (nk_FScoreFeatRank(Y,L))';

    case 'rgs'
        if ~isempty(opt) && ~isempty(Params_desc); 
            IN.RGS.extra_param.k = nk_ReturnParam('K',Params_desc, opt); 
            IN.RGS.extra_param.beta = nk_ReturnParam('Beta',Params_desc, opt); 
        end
        if VERBOSE, fprintf(' RGS'); end
        IN.W = RGS(Y, L, IN.RGS.extra_param)'; 

    case {'libsvm','liblin'}
        if ~isempty(opt) && ~isempty(Params_desc); 
            IN.SVM.SlackParam = nk_ReturnParam('Slack',Params_desc, opt); 
            IN.SVM.EpsParam = nk_ReturnParam('Epsilon',Params_desc, opt); 
            IN.SVM.NuParam = nk_ReturnParam('Nu',Params_desc, opt); 
        end
        if strcmp(IN.SVM.modeflag,'regression'), L = nk_ScaleData(L,0,1); end
        if isfield(IN.SVM,'evalperf'), evalperf = IN.SVM.evalperf; else evalperf = 1; end
        IN.W = abs(nk_SVMFeatRank(Y, L, IN.SVM, evalperf))'; 

    case 'relief'
        [~,IN.W] = relieff(Y, L, IN.Relief.k);
        
    case 'anova'
        IN.X = [ones(size(L,1),1) L]; 
        IN = nk_PerfANOVAObj(Y,IN);
        IN.W = IN.R2;
    
    case 'pls'
        [Yrecon,IN.PLS] = nk_PerfPLSObj(L,Y,IN.PLS);
        if isfield(IN,'curglabel') && ~isempty(IN.curglabel)
            Yrecon_LO = nk_PerfPLSObj(IN.curlabel(~IN.curglabel),[], IN.PLS);
            tYrecon = zeros(size(oY));
            tYrecon(IN.curglabel,:)= Yrecon;
            tYrecon(~IN.curglabel,:)= Yrecon_LO;
            Yrecon = tYrecon; clear tYrecon Yrecon_LO
        end
        IN.W = abs(IN.PLS.YL);
        IN.Yrecon = Yrecon;
        IN.plsdev = true;
        IN.weightmethod = 1;
        
    case 'extern'
        IN.W = IN.EXTERN;
end
    
% Options 3 & 4 require to compute a threshold (Do this using
% percentile method)
if size(IN.W,2) == 1; IN.W = IN.W'; end
if IN.weightmethod == 2, IN.W = 1-IN.W; end
% Make sure there are no NaNs in the weight vector
IN.W(isnan(IN.W))=0;
end