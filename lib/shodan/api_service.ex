defmodule Shodan.APIService do
  require Logger
  require BroadwayHelper

  use GenServer

  # GenServer callback

  @impl true
  def init(memo), do: {:ok, memo}

  defp no_hosts(false, {query, _, pages}, memo) do
    Logger.info("No more results, the query ran its course")
    # We have finished
    memo.update({query, :end, pages})
  end

  defp no_hosts(true, {query, current_page, pages}, memo) do
    Logger.error("Insufficient credit, next page to fetch is #{current_page}")
    # No more credit :(
    memo.update({query, :empty_credit, pages})
  end

  @impl true
  def handle_info(:next_page, memo) do
    {query, current_page, pages} = state = memo.get()

    Logger.info("Fetching page #{current_page} of query: '#{query}'")

    # Fetch
    resp = Shodan.API.host_search(query, current_page)
    hosts = resp
            |> Map.get(:matches, [])
            |> Enum.map(&(Shodan.HostExtractor.match_to_host(&1)))

    # Manage output
    case length(hosts) do
      0 -> 
        resp
        |> Shodan.API.insufficient_credit_error?
        |> no_hosts(state, memo)

        {:stop, :normal, memo}

      len ->
        Logger.info("Scrapped #{len} additional matches")
        Shodan.API.get_progress(resp, current_page)

        # Dispatch hosts to the ValidationPipeline
        BroadwayHelper.transform_and_push_messages(ValidationPipeline, hosts)

        # Schedule next page's fetch in a second
        Process.send_after(self(), :next_page, 1_000)

        # Update our Agent's state for the next page
        memo.update({query, current_page + 1, [current_page | pages]})

        {:noreply, memo}
    end
  end

  @impl true
  def handle_call({:search_all, query, start_page}, _from, memo) do
    # Kick-off fetching
    :ok = Process.send(self(), :next_page, [])

    # Register the query
    memo.update({query, start_page, []})

    {:reply, :ok, memo}
  end

  @impl true
  def handle_call(:check_credit, _from, memo) do
    query_credits = Shodan.API.api_info()
                    |> Map.get(:query_credits)
    {:reply, {:ok, query_credits}, memo}
  end

  # Public api

  def start_link(memo) do
    GenServer.start_link(__MODULE__, memo, name: APIService)
  end

  def search_all(query, start_page \\ 1) do
    GenServer.call(APIService, {:search_all, query, start_page})
  end

  def check_credit() do
    GenServer.call(APIService, :check_credit)
  end
end
