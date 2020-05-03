defmodule Shodan.SSDPScanner do
  require Logger

  @timeout 1_000

  def ssdp_discovery(ip, port \\ 1900) do
    Logger.info("Sending discovery message to #{ip}:#{port}")

    {:ok, ip} = ip
                |> String.to_charlist()
                |> :inet.parse_address()

    {:ok, sock} = :gen_udp.open(0, [:binary, {:active, false}])

    msg = [
      'M-SEARCH * HTTP/1.1',
      'HOST: 239.255.255.250:#{port}',
      'ST: upnp:rootdevice',
      'MX: 2',
      'MAN: "ssdp:discover"',
      '',
    ]
    |> Enum.join("\r\n")
    |> String.to_charlist()

    :ok = :gen_udp.send(sock, ip, port, msg)
    Logger.debug("Message sent")

    ret = case :gen_udp.recv(sock, 0, @timeout) do
      {:ok, {^ip, ^port, res}} ->
        Logger.info("Got a response: #{inspect res}")
        {:ok, res}

      {:error, :timeout} -> 
        Logger.debug("Timeout reached")
        {:error, :timeout}
    end

    :gen_udp.close(sock)

    ret
  end
end
