defmodule RPLidar.Framer.Accumulator do
  @moduledoc false

  alias RPLidar.Frame

  @deg_to_rad :math.pi() / 180.0

  def new(scale) do
    {[], false, 0, 0, scale}
  end

  # empty list and angle is already past 180
  def step({[], _, _, _, s}, a, d, q, ts) when a > 180.0,
    do: {:cont, {insert(a, d, q, s, []), true, ts, ts, s}}

  # empty list and angle is not yet past 180
  def step({[], _, _, _, s}, a, d, q, ts),
    do: {:cont, {insert(a, d, q, s, []), false, ts, ts, s}}

  # list where we are past 0 and the previous angle was past 315 -> NEW FRAME
  def step({[{last_angle, _, _, _} | _] = points, true, ts0, ts1, s}, a, d, q, ts)
      when a < 45.0 and last_angle > 315.0 do
    {:frame, Frame.new(points, ts0, ts1), {insert(a, d, q, s, []), false, ts, ts, s}}
  end

  # Normal insert after we passed 180
  def step({frame, true, ts0, _, s}, a, d, q, ts) do
    {:cont, {insert(a, d, q, s, frame), true, ts0, ts, s}}
  end

  # Insert and before we have passed 180
  def step({frame, false, ts0, _, s}, a, d, q, ts) do
    {:cont, {insert(a, d, q, s, frame), a > 135.0 && a < 225.0, ts0, ts, s}}
  end

  def insert(_, d, q, _, list) when d == 0 or q < 1, do: list

  def insert(a, d, _, s, list) do
    r = a * @deg_to_rad
    d = d * s
    x = :math.sin(r) * d
    y = :math.cos(r) * d
    insert_sort({a, d, x, y}, list)
  end

  defp insert_sort(pt, []), do: [pt]

  defp insert_sort({a, _, _, _} = pt, [{b, _, _, _} | _] = frame) when a >= b do
    [pt | frame]
  end

  defp insert_sort(pt, [ptb | rest]) do
    [ptb | insert_sort(pt, rest)]
  end
end
