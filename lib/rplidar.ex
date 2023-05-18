defmodule RPLidar do
  @moduledoc """
  Module for interfacing with the RPLidar A1/A2/A3 family of 360-degree LiDAR sensors.  The `RPLidar` module is a GenServer that handles communication to and from the LiDAR device via a UART connection and an optional GPIO for motor control.

  Once connected and started, this process will send messages to the parent process (or a designated process) the decoded data received from the sensor.

  ## Basic Usage

  Once the RPLidar process is started, calling `enable_motor` will start the motor spinning and calling `start_scan` will start to receive and decode the packets from the sensor.  The calling process (or a PID passed to the `start_link` function) will start to receive `:lidar_packet` messages as each one is received from the sensor. These packets contain the decoded information for each sensed point in the format `{:lidar_packet, angle, range, quality, received_at}`:

  * `angle` - angle in degrees clockwise that the sensor was pointing when the point was sensed
  * `range` - range measurement at the given angle in millimeters
  * `quality` - quality measure of the laser return where `0` is no return and `255` is a full laser return
  * `received_at` - the value of `System.monotonic_time()` when the packet was received

  ```elixir
  def init(_) do
    {:ok, pid} = RPLidar.start_link(uart_device: "ttyS0", motor_enable_pin: 18)

    :ok = RPLidar.enable_motor(pid)
    :ok = RPLidar.start_scan(pid)
    # ...
  end

  def handle_info({:lidar_packet, angle, range, quality, received_at}, state) do
    # ...
    {:noreply, state}
  end
  ```

  To convert from `angle` and `range` to `(x,y)` coordinates (in meters):

  ```elixir
  r = angle * Math.pi() / 180.0
  d = range / 1000
  x = :math.sin(r) * d
  y = :math.cos(r) * d
  ```
  """
  use GenServer

  alias __MODULE__.Comm
  require Logger

  @options ~w(motor_enable_pin uart_device filter parent)a

  @doc """
  Enable the motor (sets the GPIO selected with the `motor_enable_pin` option to HIGH, which starts the motor spinning.

  Note that the datasheet for the RPLidar A1 requires the motor enable pin to be set to the VIN voltage of the motor.  In
  cases where you are supplying, a voltage separate from the voltage of the GPIO pins of your device, you will have to enable
  the motor in a different way.
  """
  @spec enable_motor(GenServer.server()) :: :ok
  def enable_motor(pid), do: GenServer.cast(pid, :enable_motor)

  @doc """
  Disables the motor.
  """
  @spec disable_motor(GenServer.server()) :: :ok
  def disable_motor(pid), do: GenServer.cast(pid, :disable_motor)

  @doc """
  Polls the device for hardware and firmware info
  """
  @spec get_info(GenServer.server()) :: Comm.info()
  def(get_info(pid), do: GenServer.call(pid, :get_info))

  @doc """
  Signals the device to start sending measurements.

  Note: Using the normal scan command, the device won't send any measurements until the sensor motor reaches
  a minimum RPM.  Therefore if you call `enable_motor/1` after or just before calling `start_scan`/1, there may be a delay before data is received by the parent process. To start sending measurements immediately regardless of motor speed, call `force_scan/1` after calling `start_scan/1`.
  """
  @spec start_scan(GenServer.server()) :: :ok
  def start_scan(pid), do: GenServer.cast(pid, :start_scan)

  @doc """
  After `start_scan/1` is called, calling this function will force the device to send measurements without waiting for the motor to reach a threshold RPM. 
  """
  @spec force_scan(GenServer.server()) :: :ok
  def force_scan(pid), do: GenServer.cast(pid, :force_scan)

  @doc """
  Signals the device to stop sending measurements.
  """
  @spec stop_scan(GenServer.server()) :: :ok
  def stop_scan(pid), do: GenServer.cast(pid, :stop_scan)

  @doc """
  Resets the device.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(pid), do: GenServer.cast(pid, :reset)

  @doc """
  Starts the RPLidar process.

  ### Options

  * `uart_device` - UART port to which the LiDAR is connected
  * `motor_enable_pin` - GPIO pin for controlling the motor on the LiDAR sensor
  * `filter` - if set to `true`, points with range of `0.0` or a quailty of `0` will be dropped before sending to the receiving process. (default: `false`)
  * `parent` - the PID to send points to (default: `self()`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      Keyword.take(opts, @options) |> Keyword.put_new(:parent, self()),
      Keyword.drop(opts, @options)
    )
  end

  @impl true
  def init(opts) do
    gpio =
      case Keyword.get(opts, :motor_enable_pin) do
        nil ->
          nil

        pin ->
          {:ok, gpio} = Circuits.GPIO.open(pin, :output)
          :ok = Circuits.GPIO.write(gpio, 0)
      end

    device = Keyword.get(opts, :uart_device, "ttyS0")
    {:ok, uart} = Circuits.UART.start_link()
    :ok = Circuits.UART.open(uart, device, speed: 115_200, active: false)

    {:ok,
     %{
       gpio: gpio,
       uart: uart,
       buffer: "",
       scanning: false,
       parent: Keyword.get(opts, :parent),
       filter: Keyword.get(opts, :filter, false)
     }}
  end

  @impl true
  def handle_call(:get_info, _, state) do
    :ok = Circuits.UART.write(state.uart, <<0xA5, 0x50>>)
    :timer.sleep(10)
    {:ok, data} = Circuits.UART.read(state.uart)
    {:ok, info} = Comm.decode_get_info(data)
    {:reply, info, state}
  end

  @impl true
  def handle_cast(:enable_motor, %{gpio: nil} = state), do: {:noreply, state}

  def handle_cast(:enable_motor, state) do
    :ok = Circuits.GPIO.write(state.gpio, 1)
    {:noreply, state}
  end

  def handle_cast(:disable_motor, %{gpio: nil} = state), do: {:noreply, state}

  def handle_cast(:disable_motor, state) do
    :ok = Circuits.GPIO.write(state.gpio, 0)
    {:noreply, state}
  end

  def handle_cast(:start_scan, state) do
    :ok = Circuits.UART.configure(state.uart, active: true)
    :ok = Circuits.UART.write(state.uart, <<0xA5, 0x20>>)

    {:noreply, %{state | scanning: true, buffer: ""}}
  end

  def handle_cast(:force_scan, state) do
    :ok = Circuits.UART.configure(state.uart, active: true)
    :ok = Circuits.UART.write(state.uart, <<0xA5, 0x21>>)

    {:noreply, %{state | scanning: true, buffer: ""}}
  end

  def handle_cast(:stop_scan, state) do
    :ok = Circuits.UART.write(state.uart, <<0xA5, 0x25>>)
    :timer.sleep(1)
    :ok = Circuits.UART.drain(state.uart)
    :ok = Circuits.UART.configure(state.uart, active: false)

    {:noreply, %{state | scanning: false, buffer: ""}}
  end

  def handle_cast(:reset, state) do
    :ok = Circuits.UART.write(state.uart, <<0xA5, 0x40>>)
    :timer.sleep(2)
    :ok = Circuits.UART.drain(state.uart)
    :ok = Circuits.UART.configure(state.uart, active: false)
    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, _, data}, state) do
    time = System.monotonic_time()
    {result, buffer} = Comm.decode_scan(state.buffer <> data)
    :ok = process_scan(result, state.parent, state.filter, time)
    {:noreply, %{state | buffer: buffer}}
  end

  defp process_scan(nil, _, _), do: :ok
  defp process_scan({_, 0.0, _}, _, true), do: :ok
  defp process_scan({_, _, 0}, _, true), do: :ok

  defp process_scan({angle, distance, quality}, parent, _, time) do
    send(parent, {:lidar_packet, angle, distance, quality, time})
    :ok
  end
end
