defmodule Algebra.Expression do
	defmacro parse(do: blk) do
		expr = do_parse(blk)
		quote do: unquote(Macro.escape expr)
	end

	defmodule BinOp do
		defstruct [:op, :left, :right]
	end

	defmodule Constant do
		defstruct value: 0
	end

	defmodule Variable do
		defstruct [:name]
	end

	def do_parse({op, _pos, [a, b]}) when op == :+ or op == :* or op == :/, do: %BinOp{op: op, left: do_parse(a), right: do_parse(b)}
	def do_parse({:^^^, _pos, [a, b]}), do: %BinOp{op: :^, left: do_parse(a), right: do_parse(b)}
	def do_parse({:-, _pos, [a, b]}), do: %BinOp{op: :+, left: do_parse(a), right: %BinOp{op: :*, left: %Constant{value: -1}, right: do_parse(b)}}

	def do_parse(n) when is_number(n), do: %Constant{value: n}

	def do_parse({name, _pos, nil}) when is_atom(name) or is_bitstring(name) or is_binary(name), do: %Variable{name: to_string(name)}

	def simplify(ex), do: ex |> combine_order |> do_simplify

	def combine_order(ex, old \\ nil), do: ex |> do_order(old) |> do_combine(old) |> do_order(old)

	def do_order(ex, old \\ nil)
	def do_order(ex, ex), do: ex

	def do_order(ex = %BinOp{op: :*, left: left = %{__struct__: lt}, right: right = %Constant{}}, _) when lt != Constant, do: do_order(%BinOp{op: :*, left: right, right: left}, ex)
	def do_order(ex = %BinOp{op: op, left: left, right: right}, _), do: do_order(%BinOp{op: op, left: do_order(left, nil), right: do_order(right, nil)}, ex)

	def do_order(ex, _), do: ex

	defp combiner_add(amts, id, amt), do: Dict.put(amts, id, Dict.get(amts, id, 0) + amt)
	defp combiner_mul(amts, id, amt), do: Dict.put(amts, id, Dict.get(amts, id, 1) * amt)

	defp addition_combiner(queue, amts \\ %{})
	defp addition_combiner([%BinOp{op: :+, left: left, right: right} | queue], amts), do: addition_combiner([left, right | queue], amts)
	defp addition_combiner([%Constant{value: val} | queue], amts), do: addition_combiner(queue, combiner_add(amts, 1, val))
	defp addition_combiner([%BinOp{op: :*, left: %Constant{value: -1}, right: %Constant{value: val}} | queue], amts), do: addition_combiner(queue, combiner_add(amts, 1, -val))
	defp addition_combiner([%Variable{name: name} | queue], amts), do: addition_combiner(queue, combiner_add(amts, {name, 1}, 1))
	defp addition_combiner([%BinOp{op: :^, left: %Variable{name: name}, right: %Constant{value: pow}} | queue], amts), do: addition_combiner(queue, combiner_add(amts, {name, pow}, 1))
	defp addition_combiner([%BinOp{op: :*, left: %Constant{value: co}, right: %Variable{name: name}} | queue], amts), do: addition_combiner(queue, combiner_add(amts, {name, 1}, co))
	defp addition_combiner([%BinOp{op: :*, left: %Constant{value: co}, right: %BinOp{op: :^, left: %Variable{name: name}, right: %Constant{value: pow}}} | queue], amts), do: addition_combiner(queue, combiner_add(amts, {name, pow}, co))
	defp addition_combiner([], amts) do
		# IO.puts "amts = #{inspect amts}"
		keys = amts |> Dict.keys |> Enum.sort fn
			1, _ -> false
			{name, pow1}, {name, pow2} -> pow1 > pow2
			{name1, pow}, {name2, pow} -> name1 < name2
			_, _ -> true
		end
		# IO.puts "keys = #{inspect keys}"
		parts = keys |> Enum.map(fn key -> {key, amts[key]} end) |> Enum.map(fn
			{1, val} -> %Constant{value: val}
			{{name, 1}, 1} -> %Variable{name: name}
			{{name, pow}, 1} -> %BinOp{op: :^, left: %Variable{name: name}, right: %Constant{value: pow}}
			{{name, 1}, co} -> %BinOp{op: :*, left: %Constant{value: co}, right: %Variable{name: name}}
			{{name, pow}, co} -> %BinOp{op: :*, left: %Constant{value: co}, right: %BinOp{op: :^, left: %Variable{name: name}, right: %Constant{value: pow}}}
		end)
		# IO.puts "parts = #{inspect parts}"
		res = Enum.reduce(tl(parts), hd(parts), fn right, left -> %BinOp{op: :+, left: left, right: right} end)
		# IO.puts "res = #{res}"
		res
	end

	defp multiplication_combiner(queue, amts \\ %{})
	defp multiplication_combiner([%BinOp{op: :*, left: left, right: right} | queue], amts), do: multiplication_combiner([left, right | queue], amts)
	defp multiplication_combiner([ex = %BinOp{op: :+, left: left, right: right} | queue], amts), do: %BinOp{op: :*, left: multiplication_combiner(queue, amts), right: ex}
	defp multiplication_combiner([%Constant{value: val} | queue], amts), do: multiplication_combiner(queue, combiner_mul(amts, 1, val))
	defp multiplication_combiner([%Variable{name: name} | queue], amts), do: multiplication_combiner(queue, combiner_add(amts, name, 1))
	defp multiplication_combiner([%BinOp{left: %Variable{name: name}, right: %Constant{value: pow}} | queue], amts), do: multiplication_combiner(queue, combiner_add(amts, name, pow))
	defp multiplication_combiner([], amts) do
		# IO.puts "amts = #{inspect amts}"
		keys = amts |> Dict.keys |> Enum.sort fn
			_, 1 -> false
			name1, name2 when (is_binary(name1) or is_bitstring(name1)) and (is_binary(name2) or is_bitstring(name2)) -> name1 < name2
			_, _ -> true
		end
		# IO.puts "keys = #{inspect keys}"
		parts = keys |> Enum.map(fn key -> {key, amts[key]} end) |> Enum.map(fn
			{1, val} -> %Constant{value: val}
			{name, 1} -> %Variable{name: name}
			{name, pow} -> %BinOp{op: :^, left: %Variable{name: name}, right: %Constant{value: pow}}
		end)
		# IO.puts "parts = #{inspect parts}"
		res = Enum.reduce(tl(parts), hd(parts), fn right, left -> %BinOp{op: :*, left: left, right: right} end)
		# IO.puts "res = #{res}"
		res
	end

	def do_combine(ex, old \\ nil)
	def do_combine(ex, ex), do: ex

	def do_combine(ex = %BinOp{op: :+, left: %Constant{value: left}, right: %Constant{value: right}}, _), do: do_combine(%Constant{value: left + right}, ex)
	def do_combine(ex = %BinOp{op: :+}, _) do
		do_combine(addition_combiner([ex]), ex)
	end

	def do_combine(ex = %BinOp{op: :*}, _) do
		do_combine(multiplication_combiner([ex]), ex)
	end

	# def do_combine(ex = %BinOp{op: op, left: left, right: right}, _), do: do_combine(%BinOp{op: op, left: do_combine(left, nil), right: do_combine(right, nil)}, ex)

	def do_combine(ex, _), do: ex

	def do_simplify(ex, old \\ nil)
	def do_simplify(ex, ex), do: ex

	def do_simplify(ex = %BinOp{op: :+, left: %Constant{value: left}, right: %Constant{value: right}}, _), do: do_simplify(%Constant{value: left + right}, ex)
	def do_simplify(ex = %BinOp{op: :*, left: %Constant{value: left}, right: %Constant{value: right}}, _), do: do_simplify(%Constant{value: left * right}, ex)
	def do_simplify(ex = %BinOp{op: :*, left: left, right: %BinOp{op: :+, left: rl, right: rr}}, _) do
		do_simplify do_order(%BinOp{op: :+,
			left: simplify(%BinOp{op: :*, left: left, right: rl}),
			right: simplify(%BinOp{op: :*, left: left, right: rr})
		}), ex
	end
	def do_simplify(ex = %BinOp{op: :+, left: %BinOp{op: :*, left: fleft, right: sim}, right: %BinOp{op: :*, left: sleft, right: sim}}, _) do
		do_simplify(%BinOp{op: :*, left: %BinOp{op: :+, left: fleft, right: sleft}, right: sim}, ex)
	end
	def do_simplify(ex = %BinOp{op: op, left: left, right: right}, _), do: %BinOp{op: op, left: simplify(left), right: simplify(right)} |> combine_order |> do_simplify(ex)

	def do_simplify(ex, _), do: ex

	defimpl String.Chars, for: BinOp do
		defp maybe_parens(ex, op, side, other) do
			if parens?(ex, op, side, other) do
				"(#{ex})"
			else
				"#{ex}"
			end
		end
		defp maybe_parens(ex, _, _, _), do: "#{ex}"

		def parens?(%Constant{}, :+, _, _), do: false
		def parens?(%Constant{}, :*, :left, _), do: false
		def parens?(%BinOp{op: op}, op, _, _) when op == :* or op == :+ or op == :-, do: false
		def parens?(%Variable{}, _, _, _), do: false
		def parens?(%BinOp{op: :^, right: %Constant{}}, :*, :left, %Constant{}), do: true
		def parens?(%BinOp{op: :^, right: %Constant{}}, :*, :left, %BinOp{left: %Constant{}}), do: true
		def parens?(%BinOp{op: :^, right: %Constant{}}, :*, :left, _), do: false
		def parens?(%BinOp{op: :^}, :*, _, _), do: false
		def parens?(_, _, _, _), do: true

		def to_string(%BinOp{op: :^, left: left, right: right}), do: "#{left}^#{right}"
		def to_string(%BinOp{op: :*, left: left = %Constant{value: -1}, right: right}), do: "-#{maybe_parens right, :*, :right, left}"
		def to_string(%BinOp{op: :*, left: left, right: right}), do: "#{maybe_parens left, :*, :left, right}#{maybe_parens right, :*, :right, left}"
		def to_string(%BinOp{op: :+, left: left, right: %BinOp{op: :*, left: %Constant{value: -1}, right: right}}), do: "#{maybe_parens left, :-, :left, right} - #{maybe_parens right, :-, :right, left}"
		def to_string(%BinOp{op: op, left: left, right: right}), do: "#{maybe_parens left, op, :left, right} #{op} #{maybe_parens right, op, :right, left}"
	end
	defimpl String.Chars, for: Constant do
		def to_string(%Constant{value: val}), do: "#{val}"
	end
	defimpl String.Chars, for: Variable do
		def to_string(%Variable{name: name}), do: "#{name}"
	end
end