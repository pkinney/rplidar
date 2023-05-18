defmodule RPLidar.Framer do
  @moduledoc """
  The `RPLidar.Framer` module provides a process that can receive individual points and accumulate them into
  `RPLidar.Frame`s that represent a single 360-degree rotation of the sensor.  These frames are much more useful for certain operations that require a "snapshot" of the ranges to objects around the sensor.

  ### Usage

  In order to use `RPLidar.Framer`, start a `Framer` process and hand its PID to the `RPLidar.start_link/1` function.  The `Framer` process will then receive sensor measurements and will send a `:lidar_frame` message with a `RPLidar.Frame` struct for each completed 360-degree scan.

  ```elixir
  def init(_) do
  {:ok, framer} = RPLidar.Framer.start_link(scale: 0.001, quality_threshold: 80)
  {:ok, pid} = RPLidar.start_link(uart_device: "ttyS0", motor_enable_pin: 18, parent: framer, filter: true)

  :ok = RPLidar.enable_motor(pid)
  :ok = RPLidar.start_scan(pid)
  # ...
  end

  def handle_info({:lidar_frame, %RPLidar.Frame{} = frame}, state) do
  # ...
  {:noreply, state}
  end
  ```

  The `RPLidar.Frame` struct contains the points as a parameter `points`.  Each point is a tuple `{angle, range, x, y}` containnig:

  * `angle` - original angle from the raw point (in degrees)
  * `range` - original range from the raw point (in millimeters)
  * `x` and `y` - calculated Cartesian coordinates scaled by the `scale` options passed to the Framer (scaled to meters in the code above)

  """
  use GenServer

  require Logger
  alias __MODULE__.Accumulator

  @doc """
  Starts a `RPLidar.Framer` process. 
   
  ### Options

  * `scale` - Scale factor to use when converting from millimeter range to Cartesian coordinates.  For example, if set to 0.001, Cartesian coordinates will be returned in meters (default: 1.0)
  * `quality_threshold` - Any point with a quality less than the given number will be ignored in the frame (default: 1)
  * `parent` - the PID to send completed frames to (default: `self()`)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, Keyword.put_new(opts, :parent, self()), opts)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       framer: Accumulator.new(Keyword.get(opts, :scale, 1.0)),
       parent: Keyword.get(opts, :parent),
       quality_threshold: Keyword.get(opts, :quality_threshold, 1)
     }}
  end

  @impl true
  def handle_info({:lidar_packet, _, _, quality, _}, state)
      when quality < state.quality_threshold,
      do: {:noreply, state}

  def handle_info({:lidar_packet, angle, range, quality, ts}, state) do
    framer =
      case Accumulator.step(state.framer, angle, range, quality, ts) do
        {:cont, framer} ->
          framer

        {:frame, frame, framer} ->
          send(state.parent, {:lidar_frame, frame})
          framer
      end

    {:noreply, %{state | framer: framer}}
  end
end
