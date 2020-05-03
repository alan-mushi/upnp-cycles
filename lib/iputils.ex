defmodule IPUtils do
  #
  # This is a bit "heavy" but it's going to be called often, let's try and
  # fetch+parse the local IPs only once and keep them in memory.
  #

  require Logger

  import InetCidr

  use GenServer

  def start_link(opts) do
    Logger.info("Starting #{__MODULE__}, with additional_cidrs")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(additional_cidrs) when is_list(additional_cidrs) do
    local_ips = get_our_ips_cidr() ++ additional_cidrs
                |> Enum.map(&InetCidr.parse(&1, true))

    {:ok, local_ips}
  end

  @impl true
  def handle_call({:one_of_our_ips, ip}, _from, local_ips) do
    res = Enum.any?(local_ips, fn local_ip ->
      InetCidr.contains?(local_ip, InetCidr.parse_address!(ip))
    end)

    {:reply, {:ok, res}, local_ips}
  end

  @impl true
  def handle_call(:clear_cached_addrs, _from, state) do
    Logger.warn("Clearing #{length(state)} cached IP addresses")
    {:reply, {:ok, state}, []}
  end

  def get_our_ips_cidr() do
    {:ok, addrs} = :inet.getif()
    Enum.map(addrs, fn {start, _, mask} ->
      m = mask
          |> Tuple.to_list()
          |> Enum.flat_map(&Integer.digits(&1, 2))
          |> Enum.sum()

      "#{:inet.ntoa(start)}/#{m}"
    end)
  end

  def one_of_our_ips?(ip) do
    {:ok, res} = GenServer.call(__MODULE__, {:one_of_our_ips, ip})
    res
  end

  def clear_cached_addrs() do
    {:ok, res} = GenServer.call(__MODULE__, :clear_cached_addrs)
    res
  end

  def broadcast_ip?(ip) do
    # This could be improved, it's kinda lame as is
    ip == "255.255.255.255"
  end
end
