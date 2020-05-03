defmodule IPUtils.Test do
  use ExUnit.Case, async: true
  doctest IPUtils

  test "check localhost variation is in our ips" do
    assert IPUtils.one_of_our_ips?("127.0.2.23") == true
  end

  test "get all of our local ip as cidr strings" do
    assert Enum.any?(IPUtils.get_our_ips_cidr(), fn x -> x == "127.0.0.1/8" end) == true
  end
end
