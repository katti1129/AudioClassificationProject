function lossDb = knifeEdgeLoss(v)
%KNIFEEDGELOSS Return the ITU-R single knife-edge magnitude loss [dB].
%   LOSSDB = KNIFEEDGELOSS(V) evaluates the Fresnel-Kirchhoff engineering
%   approximation used in ITU-R P.526-16:
%     J(v)=0, v<=-0.78
%     J(v)=6.9+20log10(sqrt((v-0.1)^2+1)+v-0.1), otherwise.
%   The pressure-amplitude multiplier is 10^(-LOSSDB/20). For the
%   path-excess approximation used by this project, v ~= 2sqrt(delta/lambda).
%   Applying this radio recommendation to scalar sound is explicitly an
%   engineering knife-edge approximation, not a complete acoustic UTD.

arguments
    v double
end

lossDb=zeros(size(v));
active=v>-0.78;
shifted=v(active)-0.1;
lossDb(active)=6.9+20*log10(sqrt(shifted.^2+1)+shifted);
end
