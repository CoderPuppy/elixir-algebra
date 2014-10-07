alias Algebra, as: A
alias A.Expression, as: Ex
require Ex
alias A.Equation, as: Eq
require Eq

test_ex = fn ex -> IO.puts "#{ex} = #{Ex.simplify ex}" end

test_ex.(Ex.parse do: 2 + x + 1 + x^^^2 + a^^^2)
test_ex.(Ex.parse do: 2*5*x^^^2*1*a*b*7*x^^^3*b^^^10*a^^^5)
test_ex.(Ex.parse do: 2 - 1)
test_ex.(Ex.parse do: 2 * (5 + 1))
test_ex.(Ex.parse do: x * (5 + 1))
test_ex.(Ex.parse do: x^^^2 * (5 + 1))

# eq = Eq.parse do: x + 1 = 2
# IO.puts eq
# IO.puts Eq.simplify Eq

# IO.puts Eq.parse do: x > 2