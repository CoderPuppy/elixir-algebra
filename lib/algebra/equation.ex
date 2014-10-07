defmodule Algebra.Equation do
	alias Algebra.Expression, as: Ex

	defmacro parse(do: blk) do
		eq = do_parse(blk)
		quote do: unquote(Macro.escape eq)
	end

	defmodule Equality do
		defstruct [:left, :right]
	end
	defmodule Inequality do
		defstruct [:op, :left, :right]
	end

	def do_parse({:=, _pos, [left, right]}) do
		%Equality{left: Ex.do_parse(left), right: Ex.do_parse(right)}
	end
	def do_parse({op, _pos, [left, right]}) when op == :> or op == :< or op == :!= do
		%Inequality{op: op, left: Ex.do_parse(left), right: Ex.do_parse(right)}
	end

	defimpl String.Chars, for: Equality do
		def to_string(%Equality{left: left, right: right}), do: "#{left} = #{right}"
	end
	defimpl String.Chars, for: Inequality do
		def to_string(%Inequality{op: op, left: left, right: right}), do: "#{left} #{op} #{right}"
	end
end