function [nodes,weights] = gaussRule(order)
%GAUSSRULE Gauss-Legendre nodes and weights on [-1,1].
% Input order: positive integer. Outputs: row vectors, dimensionless.
% Golub-Welsch symmetric tridiagonal eigenvalue construction.
persistent savedOrder savedNodes savedWeights
if isempty(savedOrder) || savedOrder~=order
    k = (1:order-1).'; b = k./sqrt(4*k.^2-1);
    [V,D] = eig(diag(b,1)+diag(b,-1));
    [x,ix] = sort(diag(D));
    savedNodes = x.'; savedWeights = 2*V(1,ix).^2; savedOrder = order;
end
nodes = savedNodes; weights = savedWeights;
end
