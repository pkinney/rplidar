defmodule RPLidar.Frame do
  @moduledoc """
  The `RPLidar.Frame` struct contains a resultant frame produced by the `RPLidar.Framer` process.  Its contents are a list of points and the `start` and `finish` timestamps (as returned from `System.monotonic_time/0`).

  Each member of the `points` list is a tuple containing the original point data as well as the converted Cartesian coordinates (`x` and `y`) calculated by the Framer process. 

  * `angle` - original angle from the raw point (in degrees)
  * `range` - original range from the raw point (in millimeters)
  * `x` and `y` - calculated Cartesian coordinates scaled by the `scale` options passed to the Framer (scaled to meters in the code above)
  """
  defstruct ~w(points start finish)a

  @type point() :: {float(), float(), float(), float()}
  @type t() :: %__MODULE__{points: list(point()), start: integer(), finish: integer()}

  @spec new(list(point()), integer(), integer()) :: t()
  def new(points, start, finish) do
    %__MODULE__{
      points: points,
      start: start,
      finish: finish
    }
  end
end
