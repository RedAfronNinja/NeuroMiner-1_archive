function [ contfl, analysis, mapY, GD, MD, Param, P, mapYocv ] = nk_ApplyTrainedPreproc2(analysis, inp, paramfl)
% =========================================================================
% [ contfl, analysis, mapY, GD, MD, Param, P, mapYocv ] = ...
%                           nk_ApplyTrainedPreproc2(analysis, inp, paramfl)
% =========================================================================
% Main function to compute /load and return preprocessing parameters and
% preprocessed data for trained analysis chains. The functions is used by
% nk_VisModels and nk_OOCV. It identifies the smallest number of preprocessing 
% parameter combinations needed for a trained model, for which the preprocessing 
% chains have to be computed. This set of parameter combinations is then
% forwarded to nk_PerfPreprocess or nk_Prepwhere the actual computations are
% coordinated.
% 
% Input:
% -------
%
% Output:
% -------
%
% =========================================================================
% (c) Nikolaos Koutsouleris, 08/2017

global VERBOSE OOCV PREPROC SAV

mapYocv = []; mapY = []; Param = []; GD = []; MD = []; P=[];
contfl = false; 

% Load CVdatamat for current CV2 partition
if ~exist(analysis.RootPath,'dir'), analysis.RootPath = nk_DirSelector('Specify root directory of analysis'); end
if isempty(analysis.GDfilenames{inp.f,inp.d}), contfl = true; return; end
GDpath = fullfile(analysis.RootPath, analysis.GDfilenames{inp.f,inp.d});
if ~exist(GDpath,'file'), fprintf('\n%s not found! Skipping CV2 partition [%g,%g]:\n%s',GDpath, inp.f, inp.d); contfl = true; end
if VERBOSE, fprintf('\nLoading CVdatamat for CV2 partition [%g,%g]:\n%s', inp.f, inp.d, GDpath); end
T = load(GDpath);
if isfield(T,'GD'), GD = T.GD; end;
if isfield(T,'MD'), MD = T.MD; end;

nM = numel(inp.PREPROC);
Yocv = []; 

if ~isfield(inp,'saveparam'), inp.saveparam = false; end

P = cell(1, nM); mapY = cell(1, nM); mapYocv = cell(1,nM); Param = cell(1,nM);
% Check whether optimized preprocessing params exist
if isfield(inp,'optpreprocmat') && ~isempty(inp.optpreprocmat) && ~inp.saveparam
    if exist(inp.optpreprocmat{inp.f,inp.d},'file')
        fprintf('\nLoading optimized pre-processing parameters for CV2 [%g,%g]:\n%s', ...
                inp.f, inp.d, inp.optpreprocmat{inp.f,inp.d}); 
        load(inp.optpreprocmat{inp.f,inp.d}); paramfl.found = true;
    else
        if VERBOSE, fprintf('ERROR: Loading of pre-computed parameters not possible because path to file does not anymore exist. Update your paths!'); end
    end
else
    if VERBOSE, fprintf('\nComputing pre-processing parameters for CV2 [%g,%g].\n', inp.f, inp.d); end
end

% Loop through modalities ( if needed )
for n=1:nM
    
    if nM>1
        Y = inp.X(n).Y; 
        if isfield(inp.X(n),'Yocv') && ~isempty(inp.X(n).Yocv), Yocv = inp.X(n).Yocv; end
        PREPROC = inp.PREPROC{n};
    else
        Y = inp.X.Y; 
        if isfield(inp.X(n),'Yocv') && ~isempty(inp.X(n).Yocv), Yocv = inp.X.Yocv; end 
        PREPROC = inp.PREPROC; 
    end
    
    if ~isempty(OOCV) && OOCV.preproc
       fprintf('\n'); cprintf('*red','Removing offsets between training and independent test data');
       mY = mean(Y);
       mYocv = mean(Yocv);
       diffmeans = mYocv - mY;
       inp.Yocv = bsxfun(@minus,Yocv,diffmeans);             
    end
        
    paramfl.PV = inp.X(n);
    
    if VERBOSE, fprintf('\nGenerate pre-processing parameter array for CV2 partition [%g,%g].\n',inp.f,inp.d); end
    paramfl = nk_PrepPreprocParams(PREPROC, paramfl, analysis, n, inp.ll, inp.curlabel);
    
    % Param is a structure that contains all relevant info to generate the features 
    % needed by the optimized classifier / predictor system
    if paramfl.found, 
        paramfl.Param = Param{n};
    elseif isfield(paramfl,'Param')
        paramfl = rmfield(paramfl,'Param');
    end
    
    if inp.stacking
        [mapYn, Paramn, paramfln, mapYocvn] = nk_PerfPreprocessMeta(inp, inp.label, paramfl);
    else
        [mapYn, Paramn, paramfln, mapYocvn] = nk_PerfPreprocess(Y, inp, inp.label, paramfl, Yocv);
    end
    
    mapY{n} = mapYn; P{n} = paramfln; if ~isempty(mapYocvn), mapYocv{n} = mapYocvn; end
    Param{n} = Paramn; 
    clear mapYn Paramn mapYocvn
end

% Save parameters to disk
if isfield(inp,'saveparam') && inp.saveparam
    operm = inp.f; ofold = inp.d;
    OptPreprocParamFilename = nk_GenerateNMFilePath( inp.rootdir, ...
                                                            SAV.matname, ...
                                                            'OptPreprocParam', ...
                                                            [], ...
                                                            inp.varstr, ...
                                                            inp.id, ...
                                                            operm, ...
                                                            ofold);
    fprintf('\nSaving %s to disk...', OptPreprocParamFilename)
    save(OptPreprocParamFilename,'Param','ofold','operm', '-v7.3');     
end

% Transfer mapped data to appropriate container
if nM > 1
   mapY = nk_mapY2Struct(mapY, false);
   if (iscell(mapYocv) && ~sum(cellfun(@isempty,mapYocv))) || ( ~iscell(mapYocv) && ~isempty(mapYocv)), 
       mapYocv = nk_mapY2Struct(mapYocv, false); 
   end
else
    mapY = mapY{n};
    if ~isempty(mapYocv), mapYocv = mapYocv{n}; end
end
