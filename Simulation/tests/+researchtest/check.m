function t = check(caseName,name,value,expected,tolerance,unit,detail)
%CHECK Compare finite scalar measured/expected values using absolute error.
% Output: one PASS/FAIL table row. Nonfinite values fail, never pass silently.
status="FAIL";
if isfinite(value)&&isfinite(expected)&&abs(value-expected)<=tolerance,status="PASS";end
t=researchtest.row(caseName,name,status,value,expected,tolerance,unit,detail);
end
