defmodule RPLidar.Comm do
  @moduledoc """
  Internal module containing functions for decoding messages received from the RPLidar device.
  """

  import Bitwise

  @type info() :: %{
          model: non_neg_integer(),
          firmware_minor: non_neg_integer(),
          firmware_major: non_neg_integer(),
          hardware: non_neg_integer(),
          serial: binary()
        }

  @spec decode_get_info(binary()) :: {:ok, info()}
  def decode_get_info(
        <<0xA5, 0x5A, 0x14, 0x00, 0x00, 0x00, 0x04>> <>
          <<model, firmware_minor, firmware_major, hardware, serial::128>>
      ) do
    {:ok,
     %{
       model: model,
       firmware_minor: firmware_minor,
       firmware_major: firmware_major,
       hardware: hardware,
       serial: serial |> Integer.to_string(16)
     }}
  end

  @spec decode_scan(binary()) ::
          {{float(), float(), non_neg_integer()} | nil, binary()}
  def decode_scan(<<0xA5, 0x5A, 0x05, 0x00, 0x00, 0x40, 0x81>> <> rest, time),
    do: decode_scan(rest, time)

  def decode_scan(
        <<quality::6, s::1, s_inv::1, angle_a::7, 1::1, angle_b, distance_a, distance_b>> <> rest
      )
      when (s == 1 and s_inv == 0) or (s == 0 and s_inv == 1) do
    {
      {
        ((angle_b <<< 7) + angle_a) / 64,
        ((distance_b <<< 8) + distance_a) / 4,
        quality
      },
      rest
    }
  end

  def decode_scan(buffer) when byte_size(buffer) < 5, do: {nil, buffer}
  def decode_scan(_), do: {nil, ""}
end
