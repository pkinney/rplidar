defmodule RPLidar.CommTest do
  use ExUnit.Case

  alias RPLidar.Comm

  test "decode info" do
    data =
      <<165, 90, 20, 0, 0, 0, 4, 24, 29, 1, 7, 209, 163, 237, 249, 199, 226, 155, 209, 167, 227,
        158, 242, 65, 112, 67, 27>>

    {:ok, msg} = Comm.decode_get_info(data)
    assert msg.model == 24
    assert msg.firmware_major == 1
    assert msg.firmware_minor == 29
    assert msg.hardware == 7
    assert msg.serial == "D1A3EDF9C7E29BD1A7E39EF24170431B"
  end

  test "decode scan packets" do
    {{angle, range, quality}, _} = Comm.decode_scan(<<2, 1, 0, 0, 0, 62, 237, 165>>)

    assert_in_delta angle, 0.0, 0.00001
    assert_in_delta range, 0.0, 0.00001
    assert quality == 0

    {{angle, range, quality}, _} = Comm.decode_scan(<<237, 165, 0, 0, 62, 151, 166, 70, 22, 62>>)

    assert_in_delta angle, 1.28125, 0.00001
    assert_in_delta range, 3968.0, 0.00001
    assert quality == 59
  end
end
