function y = ObjectiveFunction1(n, c, L, T, tL, tY, Ps)
global TRAINFUNC RFE

[~, model] = feval(TRAINFUNC, tY, tL, 1, Ps);   
switch RFE.Wrapper.datamode
    case 1
        param = nk_GetTestPerf(tY, tL, [], model, tY);
    case 2
        param = nk_GetTestPerf(T, L, [], model, tY);
    case 3
        param = ( nk_GetTestPerf(T, L, [], model, tY) +  nk_GetTestPerf(tY, tL, [], model, tY) ) / 2;
end
rF = size(T,2)/n;
y = param - c*rF;