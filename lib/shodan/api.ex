defmodule Shodan.API do
  require Logger

  use Tesla

  plug Tesla.Middleware.BaseUrl, Application.get_env(:shodan, :api_endpoint)
  plug Tesla.Middleware.Query, [key: Application.get_env(:shodan, :api_key)]
  plug Tesla.Middleware.JSON, engine: Poison, engine_opts: [keys: :atoms]
  plug Tesla.Middleware.Logger
  plug Tesla.Middleware.Retry,
    delay: 1_000,
    max_retries: 3,
    max_delay: 5_000,
    should_retry: fn
      {:ok, %{status: status}} when status == 401 -> false
      {:ok, _} -> false
      {:error, _} -> true
    end
  plug Tesla.Middleware.Timeout, timeout: 10_000
  plug Tesla.Middleware.KeepRequest

  def api_info(full_response \\ false) when is_boolean(full_response) do
    {:ok, resp} = get("/api-info")
    if full_response, do: resp, else: resp.body
  end

  def host_search(query, page \\ 1) when is_bitstring(query) and is_integer(page) and page >= 1 do
    {:ok, resp} = get("/shodan/host/search", query: [query: query, page: page])
    resp.body
  end

  def get_progress(resp_body, page) when is_integer(page) and page >= 0 do
    total = Map.get(resp_body, :total, "?")
    res = "#{page * 100} / #{total}"
    Logger.info("progress: #{res}")
    res
  end

  def insufficient_credit_error?(%{error: msg}) do
    String.starts_with?(msg, "Insufficient query credits,")
  end

  def insufficient_credit_error?(_), do: false

  @deprecated "Use APIService.search_all() instead"
  defp has_matches?(resp) do
    resp
    |> Map.get(:matches, [])
    |> Enum.empty?
    |> Kernel.not
  end

  @deprecated "Use APIService.search_all() instead"
  def host_search_all(query, start_page \\ 1) when is_integer(start_page) and start_page >= 1 do
    Stream.interval(1_000)
    |> Stream.map(&Kernel.+(&1, start_page))
    |> Stream.map(&(host_search(query, &1)))
    |> Stream.take_while(&(has_matches?(&1))) # Take while not exhausted results
    |> Stream.flat_map(fn m -> Map.get(m, :matches, []) end)
  end

end
