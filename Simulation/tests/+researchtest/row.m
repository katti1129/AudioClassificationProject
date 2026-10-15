function t = row(caseName,check,status,measured,expected,tolerance,unit,detail)
%ROW Create one diagnostic record; scalar values use the stated UNIT.
% Inputs: case/check/status labels, measurements, tolerance and explanation.
% Output: T, one-row table; NaN means a quantity is not applicable.
t=table(string(caseName),string(check),string(status),double(measured), ...
    double(expected),double(tolerance),string(unit),string(detail), ...
    'VariableNames',{'Case','Check','Status','Measured','Expected','Tolerance','Unit','Detail'});
end
